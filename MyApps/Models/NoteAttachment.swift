import Foundation
import SwiftData

@Model
final class NoteAttachment {
    var id: UUID = UUID()
    var filename: String = "Image.jpg"
    var mimeType: String = "image/jpeg"
    var pixelWidth: Double = 0
    var pixelHeight: Double = 0
    var createdAt: Date = Date()

    @Attribute(.externalStorage) var data: Data?
    var note: QuickNote?

    init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String = "image/jpeg",
        pixelWidth: Double,
        pixelHeight: Double,
        data: Data
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.data = data
        self.createdAt = Date()
    }
}
