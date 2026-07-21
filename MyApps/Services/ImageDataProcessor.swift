import UIKit

enum ImageDataProcessor {
    static func appIconData(from sourceData: Data, targetSize: CGFloat = 320) -> Data? {
        guard let image = UIImage(data: sourceData) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let target = CGSize(width: targetSize, height: targetSize)
        let renderer = UIGraphicsImageRenderer(size: target, format: format)

        let rendered = renderer.image { context in
            UIColor.black.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: target))

            let sourceRatio = image.size.width / max(image.size.height, 1)
            let targetRatio = target.width / target.height
            let drawRect: CGRect

            if sourceRatio > targetRatio {
                let height = target.height
                let width = height * sourceRatio
                drawRect = CGRect(x: (target.width - width) / 2, y: 0, width: width, height: height)
            } else {
                let width = target.width
                let height = width / max(sourceRatio, 0.001)
                drawRect = CGRect(x: 0, y: (target.height - height) / 2, width: width, height: height)
            }

            image.draw(in: drawRect)
        }

        return rendered.jpegData(compressionQuality: 0.88)
    }
}
