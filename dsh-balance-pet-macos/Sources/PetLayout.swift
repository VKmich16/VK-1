import AppKit

/// Coordinates for the four 1536 × 1024 character images. A size preset still
/// means body height, so adding the tail does not shrink the face or balance.
enum PetLayout {
    static let artworkSize = CGSize(width: 1536, height: 1024)
    static let aspectRatio = artworkSize.width / artworkSize.height
    static let floatBand: CGFloat = 0.55
    static let tabletBounds = CGRect(x: 0, y: 0, width: 400, height: 220)

    static func windowSize(side: CGFloat) -> CGSize {
        CGSize(width: side * aspectRatio, height: side * (1 + floatBand))
    }

    static func bodyHeight(in bounds: CGRect) -> CGFloat {
        bounds.width / aspectRatio
    }

    static func spriteRect(in bounds: CGRect) -> CGRect {
        let side = bodyHeight(in: bounds)
        let size = CGSize(width: side * 0.94 * aspectRatio, height: side * 0.94)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.minY + side * 0.03,
                      width: size.width, height: size.height)
    }

    static func tabletTransform(in bounds: CGRect, character: PetCharacter = .deepseek) -> CGAffineTransform {
        // Convert the selected image's measured corners to bottom-origin source
        // coordinates, using the exact same scale as its sprite and alpha mask.
        let corners = character.tabletCorners
        let rect = spriteRect(in: bounds)
        let scale = rect.width / artworkSize.width
        return CGAffineTransform(a: (corners.topRight.x - corners.topLeft.x) / tabletBounds.width * scale,
                                 b: (corners.topLeft.y - corners.topRight.y) / tabletBounds.width * scale,
                                 c: (corners.topLeft.x - corners.bottomLeft.x) / tabletBounds.height * scale,
                                 d: (corners.bottomLeft.y - corners.topLeft.y) / tabletBounds.height * scale,
                                 tx: rect.minX + corners.bottomLeft.x * scale,
                                 ty: rect.minY + (artworkSize.height - corners.bottomLeft.y) * scale)
    }
}
