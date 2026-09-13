import UIKit

enum ImageCropper {
    /// Crops `image` to what is visible inside `rect` when the image is shown
    /// aspect-filled and centred inside a view of `viewSize` (matches the preview layer).
    static func crop(_ image: UIImage, toViewRect rect: CGRect, in viewSize: CGSize) -> UIImage {
        let upright = image.orientedUp()
        guard let cg = upright.cgImage, viewSize.width > 0, viewSize.height > 0 else { return image }

        let imageWidth = CGFloat(cg.width)
        let imageHeight = CGFloat(cg.height)
        let scale = max(viewSize.width / imageWidth, viewSize.height / imageHeight)
        let offsetX = (viewSize.width - imageWidth * scale) / 2
        let offsetY = (viewSize.height - imageHeight * scale) / 2

        var target = CGRect(
            x: (rect.minX - offsetX) / scale,
            y: (rect.minY - offsetY) / scale,
            width: rect.width / scale,
            height: rect.height / scale
        )
        target = target.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)).integral

        guard !target.isNull, target.width > 1, target.height > 1, let cropped = cg.cropping(to: target) else {
            return upright
        }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    /// A neutral stand-in used when no camera is available (Simulator).
    static func placeholderImage(size: CGSize = CGSize(width: 1200, height: 800)) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.93, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.80, alpha: 1).setStroke()
            let path = UIBezierPath()
            let step: CGFloat = 40
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            path.lineWidth = 1
            path.stroke()
        }
    }
}

extension UIImage {
    /// Re-draws the image so that `imageOrientation == .up` and pixels match `size`.
    func orientedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
