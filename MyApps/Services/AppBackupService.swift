import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let myAppsBackup = UTType(
        exportedAs: "com.hoangbkit.myapps.backup",
        conformingTo: .package
    )
}

struct MyAppsBackupDocument: FileDocument, Sendable {
    static var readableContentTypes: [UTType] { [.myAppsBackup, .json] }

    let package: MyAppsBackupPackage

    init(package: MyAppsBackupPackage) {
        self.package = package
    }

    init(configuration: ReadConfiguration) throws {
        package = try MyAppsBackupService.decode(fileWrapper: configuration.file)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try MyAppsBackupService.makeFileWrapper(for: package)
    }
}

struct MyAppsBackupPackage: Sendable {
    let manifest: MyAppsBackupManifest
    let apps: [BackupAppRecord]
    let notes: [BackupNoteRecord]
    let assets: [String: Data]

    var appCount: Int { apps.count }
    var noteCount: Int { notes.count }
    var attachmentCount: Int { notes.reduce(0) { $0 + $1.attachments.count } }
}

struct MyAppsBackupManifest: Codable, Sendable {
    static let formatIdentifier = "com.hoangbkit.myapps.backup"
    static let currentFormatVersion = 2

    let formatIdentifier: String
    let formatVersion: Int
    let appVersion: String
    let exportedAt: Date
    let preferences: BackupPreferencesRecord?
    let appCount: Int
    let noteCount: Int
    let attachmentCount: Int
}

struct BackupPreferencesRecord: Codable, Sendable {
    let appearanceRawValue: String
    let appSortRawValue: String
    let noteSortRawValue: String
}

struct BackupAppRecord: Codable, Sendable {
    let id: UUID
    let name: String
    let shortDescription: String
    let showsDescriptionInList: Bool
    let stageRawValue: String
    let platformRawValue: String
    let liveVersion: String
    let developmentVersion: String
    let projectStatusRawValue: String
    let businessModelRawValue: String
    let totalIncome: Double?
    let monthlyRecurringRevenue: Double?
    let currencyCode: String
    let listDisplayFieldsRawValue: String
    let isPinned: Bool
    let pinnedAt: Date?
    let iconAssetPath: String?

    // Kept only so P3.4 JSON backups can still be restored.
    let iconData: Data?

    let defaultIconStyleRawValue: String
    let createdAt: Date
    let updatedAt: Date
}

struct BackupNoteRecord: Codable, Sendable {
    let id: UUID
    let kindRawValue: String
    let title: String
    let body: String
    let isPinned: Bool
    let createdAt: Date
    let updatedAt: Date
    let appID: UUID?
    let checklistItems: [BackupChecklistRecord]
    let attachments: [BackupAttachmentRecord]
}

struct BackupChecklistRecord: Codable, Sendable {
    let id: UUID
    let text: String
    let isCompleted: Bool
    let sortOrder: Int
    let createdAt: Date
}

struct BackupAttachmentRecord: Codable, Sendable {
    let id: UUID
    let filename: String
    let mimeType: String
    let pixelWidth: Double
    let pixelHeight: Double
    let createdAt: Date
    let assetPath: String?

    // Kept only so P3.4 JSON backups can still be restored.
    let data: Data?
}

private struct LegacyBackupPayload: Codable, Sendable {
    let formatVersion: Int
    let exportedAt: Date
    let preferences: BackupPreferencesRecord?
    let apps: [BackupAppRecord]
    let notes: [BackupNoteRecord]
}

enum MyAppsBackupError: LocalizedError, Sendable {
    case unreadableFile
    case unsupportedVersion(Int)
    case invalidBackup
    case missingRequiredFile(String)
    case missingAsset(String)
    case unsafeAssetPath(String)
    case contentCountMismatch

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "The selected backup file could not be read."
        case let .unsupportedVersion(version):
            "This backup uses unsupported format version \(version)."
        case .invalidBackup:
            "The selected file is not a valid MyApps backup."
        case let .missingRequiredFile(filename):
            "The backup is missing the required file \(filename)."
        case let .missingAsset(path):
            "The backup is missing an image asset at \(path)."
        case let .unsafeAssetPath(path):
            "The backup contains an invalid asset path: \(path)."
        case .contentCountMismatch:
            "The backup manifest does not match its contents."
        }
    }
}

enum MyAppsBackupService {
    private static let manifestFilename = "manifest.json"
    private static let appsFilename = "apps.json"
    private static let notesFilename = "notes.json"
    private static let assetsDirectoryName = "Assets"
    private static let appIconsDirectoryName = "AppIcons"
    private static let attachmentsDirectoryName = "Attachments"

    @MainActor
    static func makePackage(apps: [ManagedApp], notes: [QuickNote]) -> MyAppsBackupPackage {
        var assets: [String: Data] = [:]

        let appRecords = apps
            .sorted { $0.createdAt < $1.createdAt }
            .map { app in
                let iconAssetPath: String?
                if let iconData = app.iconData {
                    let path = "\(assetsDirectoryName)/\(appIconsDirectoryName)/\(app.id.uuidString.lowercased()).jpg"
                    assets[path] = iconData
                    iconAssetPath = path
                } else {
                    iconAssetPath = nil
                }

                return BackupAppRecord(
                    id: app.id,
                    name: app.name,
                    shortDescription: app.shortDescription,
                    showsDescriptionInList: app.showsDescriptionInList,
                    stageRawValue: app.stageRawValue,
                    platformRawValue: app.platformRawValue,
                    liveVersion: app.liveVersion,
                    developmentVersion: app.developmentVersion,
                    projectStatusRawValue: app.projectStatusRawValue,
                    businessModelRawValue: app.businessModelRawValue,
                    totalIncome: app.totalIncome,
                    monthlyRecurringRevenue: app.monthlyRecurringRevenue,
                    currencyCode: app.currencyCode,
                    listDisplayFieldsRawValue: app.listDisplayFieldsRawValue,
                    isPinned: app.isPinned,
                    pinnedAt: app.pinnedAt,
                    iconAssetPath: iconAssetPath,
                    iconData: nil,
                    defaultIconStyleRawValue: app.defaultIconStyle.rawValue,
                    createdAt: app.createdAt,
                    updatedAt: app.updatedAt
                )
            }

        let noteRecords = notes
            .sorted { $0.createdAt < $1.createdAt }
            .map { note in
                let attachmentRecords = note.attachments
                    .sorted { $0.createdAt < $1.createdAt }
                    .map { attachment in
                        let assetPath: String?
                        if let data = attachment.data {
                            let fileExtension = preferredExtension(
                                filename: attachment.filename,
                                mimeType: attachment.mimeType
                            )
                            let path = "\(assetsDirectoryName)/\(attachmentsDirectoryName)/\(attachment.id.uuidString.lowercased()).\(fileExtension)"
                            assets[path] = data
                            assetPath = path
                        } else {
                            assetPath = nil
                        }

                        return BackupAttachmentRecord(
                            id: attachment.id,
                            filename: attachment.filename,
                            mimeType: attachment.mimeType,
                            pixelWidth: attachment.pixelWidth,
                            pixelHeight: attachment.pixelHeight,
                            createdAt: attachment.createdAt,
                            assetPath: assetPath,
                            data: nil
                        )
                    }

                return BackupNoteRecord(
                    id: note.id,
                    kindRawValue: note.kindRawValue,
                    title: note.title,
                    body: note.body,
                    isPinned: note.isPinned,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt,
                    appID: note.app?.id,
                    checklistItems: note.checklistItems
                        .sorted { lhs, rhs in
                            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                            return lhs.createdAt < rhs.createdAt
                        }
                        .map {
                            BackupChecklistRecord(
                                id: $0.id,
                                text: $0.text,
                                isCompleted: $0.isCompleted,
                                sortOrder: $0.sortOrder,
                                createdAt: $0.createdAt
                            )
                        },
                    attachments: attachmentRecords
                )
            }

        let defaults = UserDefaults.standard
        let preferences = BackupPreferencesRecord(
            appearanceRawValue: defaults.string(forKey: AppAppearance.storageKey) ?? AppAppearance.system.rawValue,
            appSortRawValue: defaults.string(forKey: AppSortOption.storageKey) ?? AppSortOption.created.rawValue,
            noteSortRawValue: defaults.string(forKey: NoteSortOption.storageKey) ?? NoteSortOption.updated.rawValue
        )

        let manifest = MyAppsBackupManifest(
            formatIdentifier: MyAppsBackupManifest.formatIdentifier,
            formatVersion: MyAppsBackupManifest.currentFormatVersion,
            appVersion: "1.0 P3.4.1",
            exportedAt: Date(),
            preferences: preferences,
            appCount: appRecords.count,
            noteCount: noteRecords.count,
            attachmentCount: noteRecords.reduce(0) { $0 + $1.attachments.count }
        )

        return MyAppsBackupPackage(
            manifest: manifest,
            apps: appRecords,
            notes: noteRecords,
            assets: assets
        )
    }

    static func makeFileWrapper(for package: MyAppsBackupPackage) throws -> FileWrapper {
        try validate(package)

        let appIconWrappers = try assetWrappers(
            from: package.assets,
            directoryPath: "\(assetsDirectoryName)/\(appIconsDirectoryName)"
        )
        let attachmentWrappers = try assetWrappers(
            from: package.assets,
            directoryPath: "\(assetsDirectoryName)/\(attachmentsDirectoryName)"
        )

        let assetsWrapper = FileWrapper(directoryWithFileWrappers: [
            appIconsDirectoryName: FileWrapper(directoryWithFileWrappers: appIconWrappers),
            attachmentsDirectoryName: FileWrapper(directoryWithFileWrappers: attachmentWrappers)
        ])

        return FileWrapper(directoryWithFileWrappers: [
            manifestFilename: FileWrapper(regularFileWithContents: try encode(package.manifest)),
            appsFilename: FileWrapper(regularFileWithContents: try encode(package.apps)),
            notesFilename: FileWrapper(regularFileWithContents: try encode(package.notes)),
            assetsDirectoryName: assetsWrapper
        ])
    }

    static func decode(fileWrapper: FileWrapper) throws -> MyAppsBackupPackage {
        if fileWrapper.isRegularFile,
           let data = fileWrapper.regularFileContents {
            return try decodeLegacyJSON(data)
        }

        guard fileWrapper.isDirectory else {
            throw MyAppsBackupError.invalidBackup
        }

        let manifest: MyAppsBackupManifest = try decodeRequiredJSON(
            named: manifestFilename,
            in: fileWrapper
        )
        let apps: [BackupAppRecord] = try decodeRequiredJSON(
            named: appsFilename,
            in: fileWrapper
        )
        let notes: [BackupNoteRecord] = try decodeRequiredJSON(
            named: notesFilename,
            in: fileWrapper
        )

        let package = MyAppsBackupPackage(
            manifest: manifest,
            apps: apps,
            notes: notes,
            assets: collectAssets(from: fileWrapper)
        )
        try validate(package)
        return package
    }

    static func load(from url: URL) throws -> MyAppsBackupPackage {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let wrapper = try FileWrapper(url: url, options: [.immediate])
        return try decode(fileWrapper: wrapper)
    }

    @MainActor
    static func restore(_ package: MyAppsBackupPackage, in modelContext: ModelContext) throws {
        try validate(package)

        do {
            for attachment in try modelContext.fetch(FetchDescriptor<NoteAttachment>()) {
                modelContext.delete(attachment)
            }
            for item in try modelContext.fetch(FetchDescriptor<ChecklistItem>()) {
                modelContext.delete(item)
            }
            for note in try modelContext.fetch(FetchDescriptor<QuickNote>()) {
                modelContext.delete(note)
            }
            for app in try modelContext.fetch(FetchDescriptor<ManagedApp>()) {
                modelContext.delete(app)
            }

            var restoredApps: [UUID: ManagedApp] = [:]

            for record in package.apps {
                let iconData = try resolvedData(
                    assetPath: record.iconAssetPath,
                    legacyData: record.iconData,
                    assets: package.assets
                )

                let app = ManagedApp(
                    name: record.name,
                    shortDescription: record.shortDescription,
                    showsDescriptionInList: record.showsDescriptionInList,
                    platform: AppPlatform(rawValue: record.platformRawValue) ?? .iOS,
                    liveVersion: record.liveVersion,
                    developmentVersion: record.developmentVersion,
                    projectStatus: ProjectStatus(rawValue: record.projectStatusRawValue) ?? .building,
                    businessModel: BusinessModel(rawValue: record.businessModelRawValue) ?? .freemium,
                    totalIncome: record.totalIncome,
                    monthlyRecurringRevenue: record.monthlyRecurringRevenue,
                    currencyCode: record.currencyCode,
                    listDisplayFields: record.listDisplayFieldsRawValue
                        .split(separator: ",")
                        .compactMap { AppListField(rawValue: String($0)) },
                    iconData: iconData,
                    defaultIconStyle: DefaultAppIconStyle(rawValue: record.defaultIconStyleRawValue) ?? .ocean,
                    isPinned: record.isPinned
                )

                app.id = record.id
                app.stageRawValue = record.stageRawValue
                app.platformRawValue = record.platformRawValue
                app.version = record.liveVersion
                app.developmentVersion = record.developmentVersion
                app.projectStatusRawValue = record.projectStatusRawValue
                app.businessModelRawValue = record.businessModelRawValue
                app.totalIncome = record.totalIncome
                app.monthlyRecurringRevenue = record.monthlyRecurringRevenue
                app.currencyCode = record.currencyCode
                app.listDisplayFieldsRawValue = record.listDisplayFieldsRawValue
                app.isPinned = record.isPinned
                app.pinnedAt = record.pinnedAt
                app.iconData = iconData
                app.defaultIconStyleRawValue = record.defaultIconStyleRawValue
                app.createdAt = record.createdAt
                app.updatedAt = record.updatedAt

                modelContext.insert(app)
                restoredApps[record.id] = app
            }

            for record in package.notes {
                let note = QuickNote(markdown: record.body)
                note.id = record.id
                note.kindRawValue = record.kindRawValue
                note.title = record.title
                note.body = record.body
                note.isPinned = record.isPinned
                note.createdAt = record.createdAt
                note.updatedAt = record.updatedAt
                note.app = record.appID.flatMap { restoredApps[$0] }
                modelContext.insert(note)

                for itemRecord in record.checklistItems {
                    let item = ChecklistItem(
                        text: itemRecord.text,
                        isCompleted: itemRecord.isCompleted,
                        sortOrder: itemRecord.sortOrder
                    )
                    item.id = itemRecord.id
                    item.createdAt = itemRecord.createdAt
                    modelContext.insert(item)
                    note.checklistItems.append(item)
                }

                for attachmentRecord in record.attachments {
                    guard let data = try resolvedData(
                        assetPath: attachmentRecord.assetPath,
                        legacyData: attachmentRecord.data,
                        assets: package.assets
                    ) else {
                        continue
                    }

                    let attachment = NoteAttachment(
                        id: attachmentRecord.id,
                        filename: attachmentRecord.filename,
                        mimeType: attachmentRecord.mimeType,
                        pixelWidth: attachmentRecord.pixelWidth,
                        pixelHeight: attachmentRecord.pixelHeight,
                        data: data
                    )
                    attachment.createdAt = attachmentRecord.createdAt
                    modelContext.insert(attachment)
                    note.attachments.append(attachment)
                }
            }

            try modelContext.save()

            if let preferences = package.manifest.preferences {
                let defaults = UserDefaults.standard
                defaults.set(preferences.appearanceRawValue, forKey: AppAppearance.storageKey)
                defaults.set(preferences.appSortRawValue, forKey: AppSortOption.storageKey)
                defaults.set(preferences.noteSortRawValue, forKey: NoteSortOption.storageKey)
            }
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private static func decodeRequiredJSON<T: Decodable>(
        named filename: String,
        in root: FileWrapper
    ) throws -> T {
        guard let wrapper = root.fileWrappers?[filename],
              wrapper.isRegularFile,
              let data = wrapper.regularFileContents else {
            throw MyAppsBackupError.missingRequiredFile(filename)
        }

        do {
            return try decode(T.self, from: data)
        } catch {
            throw MyAppsBackupError.invalidBackup
        }
    }

    private static func decodeLegacyJSON(_ data: Data) throws -> MyAppsBackupPackage {
        let payload: LegacyBackupPayload
        do {
            payload = try decode(LegacyBackupPayload.self, from: data)
        } catch {
            throw MyAppsBackupError.invalidBackup
        }

        guard payload.formatVersion > 0,
              payload.formatVersion < MyAppsBackupManifest.currentFormatVersion else {
            throw MyAppsBackupError.unsupportedVersion(payload.formatVersion)
        }

        let manifest = MyAppsBackupManifest(
            formatIdentifier: MyAppsBackupManifest.formatIdentifier,
            formatVersion: payload.formatVersion,
            appVersion: "1.0 P3.4",
            exportedAt: payload.exportedAt,
            preferences: payload.preferences,
            appCount: payload.apps.count,
            noteCount: payload.notes.count,
            attachmentCount: payload.notes.reduce(0) { $0 + $1.attachments.count }
        )

        let package = MyAppsBackupPackage(
            manifest: manifest,
            apps: payload.apps,
            notes: payload.notes,
            assets: [:]
        )
        try validate(package)
        return package
    }

    private static func validate(_ package: MyAppsBackupPackage) throws {
        let manifest = package.manifest

        guard manifest.formatIdentifier == MyAppsBackupManifest.formatIdentifier else {
            throw MyAppsBackupError.invalidBackup
        }
        guard manifest.formatVersion > 0,
              manifest.formatVersion <= MyAppsBackupManifest.currentFormatVersion else {
            throw MyAppsBackupError.unsupportedVersion(manifest.formatVersion)
        }
        guard manifest.appCount == package.apps.count,
              manifest.noteCount == package.notes.count,
              manifest.attachmentCount == package.attachmentCount else {
            throw MyAppsBackupError.contentCountMismatch
        }

        guard Set(package.apps.map(\.id)).count == package.apps.count,
              Set(package.notes.map(\.id)).count == package.notes.count else {
            throw MyAppsBackupError.invalidBackup
        }

        let appIDs = Set(package.apps.map(\.id))
        guard package.notes.allSatisfy({ note in
            guard let appID = note.appID else { return true }
            return appIDs.contains(appID)
        }) else {
            throw MyAppsBackupError.invalidBackup
        }

        for record in package.apps {
            try validateAssetReference(
                record.iconAssetPath,
                legacyData: record.iconData,
                expectedDirectory: "\(assetsDirectoryName)/\(appIconsDirectoryName)/",
                assets: package.assets
            )
        }

        var checklistIDs = Set<UUID>()
        var attachmentIDs = Set<UUID>()
        for note in package.notes {
            for checklistItem in note.checklistItems {
                guard checklistIDs.insert(checklistItem.id).inserted else {
                    throw MyAppsBackupError.invalidBackup
                }
            }

            for attachment in note.attachments {
                guard attachmentIDs.insert(attachment.id).inserted,
                      attachment.assetPath != nil || attachment.data != nil else {
                    throw MyAppsBackupError.invalidBackup
                }
                try validateAssetReference(
                    attachment.assetPath,
                    legacyData: attachment.data,
                    expectedDirectory: "\(assetsDirectoryName)/\(attachmentsDirectoryName)/",
                    assets: package.assets
                )
            }
        }
    }

    private static func validateAssetReference(
        _ path: String?,
        legacyData: Data?,
        expectedDirectory: String,
        assets: [String: Data]
    ) throws {
        guard let path else { return }
        guard isSafeRelativePath(path), path.hasPrefix(expectedDirectory) else {
            throw MyAppsBackupError.unsafeAssetPath(path)
        }
        guard assets[path] != nil || legacyData != nil else {
            throw MyAppsBackupError.missingAsset(path)
        }
    }

    private static func resolvedData(
        assetPath: String?,
        legacyData: Data?,
        assets: [String: Data]
    ) throws -> Data? {
        if let assetPath {
            guard isSafeRelativePath(assetPath) else {
                throw MyAppsBackupError.unsafeAssetPath(assetPath)
            }
            if let data = assets[assetPath] {
                return data
            }
            if let legacyData {
                return legacyData
            }
            throw MyAppsBackupError.missingAsset(assetPath)
        }
        return legacyData
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\") else {
            return false
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }

    private static func assetWrappers(
        from assets: [String: Data],
        directoryPath: String
    ) throws -> [String: FileWrapper] {
        let prefix = directoryPath + "/"
        var wrappers: [String: FileWrapper] = [:]

        for (path, data) in assets where path.hasPrefix(prefix) {
            guard isSafeRelativePath(path) else {
                throw MyAppsBackupError.unsafeAssetPath(path)
            }
            let filename = String(path.dropFirst(prefix.count))
            guard !filename.contains("/") else {
                throw MyAppsBackupError.unsafeAssetPath(path)
            }
            wrappers[filename] = FileWrapper(regularFileWithContents: data)
        }

        return wrappers
    }

    private static func collectAssets(from root: FileWrapper) -> [String: Data] {
        guard let assetsWrapper = root.fileWrappers?[assetsDirectoryName],
              assetsWrapper.isDirectory else {
            return [:]
        }

        var assets: [String: Data] = [:]
        collectRegularFiles(
            from: assetsWrapper,
            relativePath: assetsDirectoryName,
            into: &assets
        )
        return assets
    }

    private static func collectRegularFiles(
        from wrapper: FileWrapper,
        relativePath: String,
        into assets: inout [String: Data]
    ) {
        if wrapper.isRegularFile,
           let data = wrapper.regularFileContents {
            assets[relativePath] = data
            return
        }

        guard wrapper.isDirectory,
              let children = wrapper.fileWrappers else {
            return
        }

        for (name, child) in children {
            collectRegularFiles(
                from: child,
                relativePath: "\(relativePath)/\(name)",
                into: &assets
            )
        }
    }

    private static func preferredExtension(filename: String, mimeType: String) -> String {
        if mimeType == "image/png" { return "png" }
        if mimeType == "image/heic" || mimeType == "image/heif" { return "heic" }
        if mimeType == "image/webp" { return "webp" }
        if mimeType == "image/gif" { return "gif" }

        let candidate = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let safeCharacters = CharacterSet.alphanumerics
        if !candidate.isEmpty,
           candidate.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return candidate
        }

        return "jpg"
    }
}
