import AppKit

/// Four balance expressions shared by every built-in character.
enum PetExpression: Int, CaseIterable {
    case happy = 0, nervous = 1, aloof = 2, calm = 3

    var resourceName: String? {
        switch self {
        case .happy: return nil
        case .nervous: return "sprite-expression-nervous.png"
        case .aloof: return "sprite-expression-aloof.png"
        case .calm: return "sprite-expression-calm.png"
        }
    }
}

/// Built-in characters and the original Windows sound are bundled unchanged.
enum PetAssets {
    /// Bundle lookup is independent of the current working directory. The source
    /// fallback also supports running a freshly compiled development executable.
    static func resourceURL(named name: String) -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent(name),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        // A damaged application bundle must not silently use the developer's
        // checkout. Raw development binaries may use a neighbouring Resources.
        guard Bundle.main.bundleURL.pathExtension != "app" else { return nil }
        let directory = PetPaths.executableDir
        let candidates = [directory, directory.deletingLastPathComponent()].map {
            $0.appendingPathComponent("Resources").appendingPathComponent(name)
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    struct Sprite {
        let image: CGImage
        private let bitmap: NSBitmapImageRep
        private let mask: [UInt8]
        private let maskWidth: Int
        private let maskHeight: Int
        let opaqueBounds: CGRect

        init?(url: URL) {
            guard let data = try? Data(contentsOf: url),
                  let bitmap = NSBitmapImageRep(data: data),
                  let image = bitmap.cgImage else { return nil }
            self.image = image
            self.bitmap = bitmap

            // Pre-rendered alpha mask. Feeding and iron-pot hit tests sample a
            // few thousand pixels per frame; NSBitmapImageRep.colorAt is far too
            // slow for that.
            let width = image.width, height = image.height
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            let rendered = rgba.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            var alpha = [UInt8](repeating: 0, count: width * height)
            if rendered {
                for index in 0..<(width * height) { alpha[index] = rgba[index * 4 + 3] }
            }
            var minX = width, minY = height, maxX = 0, maxY = 0
            for y in 0..<height { for x in 0..<width where alpha[y*width+x] > 32 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            } }
            opaqueBounds = minX <= maxX ? CGRect(x: CGFloat(minX)/CGFloat(width),
                y: CGFloat(height-1-maxY)/CGFloat(height),
                width: CGFloat(maxX-minX+1)/CGFloat(width), height: CGFloat(maxY-minY+1)/CGFloat(height))
                : CGRect(x: 0, y: 0, width: 1, height: 1)
            self.mask = alpha
            self.maskWidth = width
            self.maskHeight = height
        }

        /// Normalized position measured from the lower-left, like an NSView.
        /// Bitmap pixels use the opposite vertical direction.
        func isOpaque(at point: CGPoint) -> Bool {
            isOpaque(normalizedX: point.x, yFromTop: 1-point.y)
        }

        /// Fast alpha lookup; `yFromTop` is measured downwards from the top edge.
        func isOpaque(normalizedX x: CGFloat, yFromTop y: CGFloat) -> Bool {
            guard x >= 0, x < 1, y >= 0, y < 1, maskWidth > 0, maskHeight > 0 else { return false }
            let px = min(maskWidth - 1, Int(x * CGFloat(maskWidth)))
            let py = min(maskHeight - 1, Int(y * CGFloat(maskHeight)))
            return mask[py * maskWidth + px] > 8
        }
    }

    /// Recharge props. Optional: a bundle without them simply has no bowls.
    private static func load(named name: String) -> (image: CGImage, size: CGSize)? {
        guard let url = resourceURL(named: name),
              let data = try? Data(contentsOf: url),
              let bitmap = NSBitmapImageRep(data: data),
              let image = bitmap.cgImage else {
            Log.write("\(name) is missing or unreadable")
            return nil
        }
        return (image, CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
    }

    static let patHands: [CGImage] = (0..<5).compactMap { load(named: "pat_hand_\($0).png")?.image }

    private static let riceLoaded = load(named: "rice.png")
    private static let ironLoaded = load(named: "iron-bowl.png")

    static let riceArt: CGImage? = riceLoaded?.image
    static let ironArt: CGImage? = ironLoaded?.image
    static let ironArtBaseSize: CGSize = ironLoaded?.size ?? CGSize(width: 900, height: 320)

    /// Actual lower rim in normalized, bottom-origin image coordinates. Ignore
    /// translucent fringe pixels so the crown cut sits behind solid metal.
    static let ironLowerRim: [CGPoint] = {
        guard let image = ironArt else { return [] }
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 0, count: w*h*4)
        rgba.withUnsafeMutableBytes { bytes in
            let ctx = CGContext(data: bytes.baseAddress, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w*4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var points: [CGPoint] = []
        for x in 0..<w {
            for y in stride(from: h-1, through: 0, by: -1) where rgba[(y*w+x)*4+3] >= 224 {
                points.append(CGPoint(x: (CGFloat(x)+0.5)/CGFloat(w)-0.5,
                                      y: (CGFloat(h-y)-0.5)/CGFloat(h)-0.5))
                break
            }
        }
        return points
    }()


    private static let sprites: [PetCharacter: Sprite] = {
        var result: [PetCharacter: Sprite] = [:]
        for character in PetCharacter.allCases {
            guard let url = resourceURL(named: character.resourceName),
                  let sprite = Sprite(url: url) else {
                Log.write("\(character.resourceName) is missing or unreadable")
                continue
            }
            result[character] = sprite
        }
        return result
    }()

    static let deepseekOffline: Sprite? = {
        guard let url = resourceURL(named: "sprite-deepseek-offline.png"),
              let sprite = Sprite(url: url) else {
            Log.write("sprite-deepseek-offline.png is missing or unreadable")
            return nil
        }
        return sprite
    }()

    static func sprite(for character: PetCharacter) -> Sprite? { sprites[character] }

    /// Face variants are optional: a bundle without them keeps the resting face.
    private static let expressionSprites: [PetExpression: Sprite] = {
        var result: [PetExpression: Sprite] = [:]
        for expression in PetExpression.allCases {
            guard let name = expression.resourceName else { continue }
            guard let url = resourceURL(named: name), let sprite = Sprite(url: url) else {
                Log.write("\(name) is missing or unreadable")
                continue
            }
            result[expression] = sprite
        }
        return result
    }()

    /// Small transparent face patches preserve the original silhouette and save memory.
    static let facePatchRect = CGRect(x: 1010, y: 330, width: 330, height: 300)
    private static let facePatches: [String: CGImage] = {
        var images: [String: CGImage] = [:]
        for character in PetCharacter.allCases where character != .deepseek {
            for state in ["nervous", "aloof", "calm"] {
                let key = "\(character.rawValue)-\(state)"
                images[key] = load(named: "face-\(key).png")?.image
            }
        }
        return images
    }()
    static func facePatch(for character: PetCharacter, expression: PetExpression) -> CGImage? {
        guard character != .deepseek, expression != .happy else { return nil }
        let names = ["happy", "nervous", "aloof", "calm"]
        return facePatches["\(character.rawValue)-\(names[expression.rawValue])"]
    }

    static func expressionSprite(_ expression: PetExpression) -> Sprite? {
        expression == .happy ? nil : expressionSprites[expression]
    }
}
