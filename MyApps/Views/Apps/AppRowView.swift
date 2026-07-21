import SwiftUI

struct AppRowView: View {
    let name: String
    let iconData: Data?
    let defaultIconStyle: DefaultAppIconStyle
    let isPinned: Bool
    let shortDescription: String?
    let statusItems: [AppStatusItem]
    var showsChevron = true

    init(app: ManagedApp, showsChevron: Bool = true) {
        self.name = app.name
        self.iconData = app.iconData
        self.defaultIconStyle = app.defaultIconStyle
        self.isPinned = app.isPinned
        let trimmedDescription = app.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        self.shortDescription = app.showsDescriptionInList && !trimmedDescription.isEmpty
            ? trimmedDescription
            : nil
        self.statusItems = app.listStatusItems
        self.showsChevron = showsChevron
    }

    init(
        name: String,
        iconData: Data?,
        defaultIconStyle: DefaultAppIconStyle = .ocean,
        isPinned: Bool,
        shortDescription: String? = nil,
        statusItems: [AppStatusItem],
        showsChevron: Bool = true
    ) {
        self.name = name
        self.iconData = iconData
        self.defaultIconStyle = defaultIconStyle
        self.isPinned = isPinned
        self.shortDescription = shortDescription
        self.statusItems = statusItems
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            AppIconView(name: name, iconData: iconData, defaultIconStyle: defaultIconStyle, size: 64)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(name)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Pinned")
                    }
                }

                if let shortDescription {
                    Text(shortDescription)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !statusItems.isEmpty {
                    AppStatusLinesView(items: statusItems)
                }
            }

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 24)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.appCardRadius, style: .continuous))
        .surfaceCard(cornerRadius: AppTheme.appCardRadius)
    }
}
