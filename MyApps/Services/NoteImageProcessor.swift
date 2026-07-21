import UIKit

struct ProcessedNoteImage {
    let data: Data
    let pixelWidth: Double
    let pixelHeight: Double
}

enum NoteImageProcessor {
    static func process(data: Data, maximumDimension: CGFloat = 2400) -> ProcessedNoteImage? {
        guard let image = UIImage(data: data) else { return nil }

        let sourceSize = image.size
        let longest = max(sourceSize.width, sourceSize.height)
        let scale = longest > maximumDimension ? maximumDimension / longest : 1
        let targetSize = CGSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.systemBackground.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let output = rendered.jpegData(compressionQuality: 0.88) else { return nil }
        return ProcessedNoteImage(
            data: output,
            pixelWidth: targetSize.width,
            pixelHeight: targetSize.height
        )
    }
}
