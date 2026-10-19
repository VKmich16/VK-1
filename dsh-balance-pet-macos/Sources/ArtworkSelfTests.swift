import AppKit

// Behavioral regressions exercise the actual bundled artwork, without user settings.
enum ArtworkSelfTests {
    private final class ImageOnlyView: NSView {
        let image: CGImage
        init(image: CGImage, frame: CGRect) {
            self.image = image
            super.init(frame: frame)
        }
        required init?(coder: NSCoder) { fatalError("unused") }
        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.clear(bounds)
            ctx.interpolationQuality = .high
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.draw(image, in: PetLayout.spriteRect(in: bounds))
            ctx.endTransparencyLayer()
        }
    }

    private struct Fixture {
        let sprite: PetAssets.Sprite
        let bitmap: NSBitmapImageRep
        let leftLandmark: CGPoint
    }

    private static func normalized(_ source: CGPoint) -> CGPoint {
        CGPoint(x: source.x / 1536, y: 1 - source.y / 1024)
    }

    // Independently measured whale tail, dragon tail, left hair mass, furry tail.
    private static func leftLandmark(for character: PetCharacter) -> CGPoint {
        switch character {
        case .deepseek: return CGPoint(x: 300, y: 450)
        case .gpt: return CGPoint(x: 100, y: 400)
        case .claude: return CGPoint(x: 450, y: 850)
        case .gemini: return CGPoint(x: 180, y: 500)
        }
    }

    private static func renderedData(_ view: NSView) -> Data? {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    static func run(_ expect: (Bool, String) -> Void) {
        var fixtures: [PetCharacter: Fixture] = [:]
        for character in PetCharacter.allCases {
            guard let sprite = PetAssets.sprite(for: character),
                  let url = PetAssets.resourceURL(named: character.resourceName),
                  let data = try? Data(contentsOf: url),
                  let bitmap = NSBitmapImageRep(data: data) else {
                expect(false, "\(character.displayName): bundled sprite loads")
                continue
            }
            expect(sprite.image.width == 1536 && sprite.image.height == 1024,
                   "\(character.displayName): 1536 × 1024 sprite loads")
            let left = leftLandmark(for: character)
            fixtures[character] = Fixture(sprite: sprite, bitmap: bitmap, leftLandmark: left)
            expect(sprite.isOpaque(at: normalized(left)), "\(character.displayName): left silhouette has an interactive alpha mask")
            expect(sprite.isOpaque(at: normalized(CGPoint(x: 1150, y: 500))),
                   "\(character.displayName): face has an interactive alpha mask")
            expect(!sprite.isOpaque(at: normalized(CGPoint(x: 450, y: 100))),
                   "\(character.displayName): empty upper-left space is transparent")
        }

        for preset in PetController.sizePresets {
            let side = preset.side
            let frame = CGRect(origin: .zero, size: PetLayout.windowSize(side: side))

            // Independently calculate placement from source landmarks instead of
            // relying on the production rectangle used by drawing and hit testing.
            func point(_ source: CGPoint) -> CGPoint {
                CGPoint(x: side * 0.045 + source.x * side * 0.94 / 1024,
                        y: side * 0.03 + (1024 - source.y) * side * 0.94 / 1024)
            }

            for character in PetCharacter.allCases {
                guard let fixture = fixtures[character] else { continue }
                let name = "\(character.displayName), \(Int(side))pt"
                let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                let connectedModel = PetModel()
                connectedModel.apply(reading: BalanceReading(normalCny: 38.61, bonusCny: 0, spentCny: nil, raw: ""), snap: true)
                let view = PetView(model: connectedModel, character: character)
                window.contentView = view
                let rect = PetLayout.spriteRect(in: view.bounds)
                expect(abs(rect.width / rect.height - 1.5) < 0.00001
                       && abs(rect.height - side * 0.94) < 0.00001,
                       "\(name): source aspect ratio and character height are preserved")
                expect(view.containsInteractivePoint(point(fixture.leftLandmark)), "\(name): left silhouette accepts clicks")
                expect(view.containsInteractivePoint(point(CGPoint(x: 1150, y: 500))), "\(name): face accepts clicks")
                expect(!view.containsInteractivePoint(point(CGPoint(x: 450, y: 100))), "\(name): transparent interior passes clicks through")
                expect(!view.containsInteractivePoint(CGPoint(x: 1, y: 1)), "\(name): outer margin passes clicks through")
                expect(!view.containsInteractivePoint(CGPoint(x: frame.midX, y: side * 1.2)),
                       "\(name): floating amounts pass clicks through")

                // Check actual PNG pixels: shifted text anchors must fail when
                // they cross hair, hands, or the bezel.
                let transform = PetLayout.tabletTransform(in: view.bounds, character: character)
                var blackScreenOnly = true
                for row in 0...10 {
                    for column in 0...10 {
                        let panel = CGPoint(x: CGFloat(column) * 40, y: CGFloat(row) * 22)
                        let mapped = panel.applying(transform)
                        let x = Int((mapped.x - side * 0.045) * 1024 / (side * 0.94))
                        let y = Int(1024 - (mapped.y - side * 0.03) * 1024 / (side * 0.94))
                        guard x >= 0, x < fixture.bitmap.pixelsWide, y >= 0, y < fixture.bitmap.pixelsHigh,
                              let color = fixture.bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                            blackScreenOnly = false
                            continue
                        }
                        if color.alphaComponent < 0.95
                            || max(color.redComponent, color.greenComponent, color.blueComponent) > 0.15 {
                            blackScreenOnly = false
                        }
                    }
                }
                expect(blackScreenOnly, "\(name): all 121 text-region samples lie on the black tablet screen")
                let motionBounds = rect.insetBy(dx: -min(3.2, side * 0.025),
                                               dy: -min(3.2, side * 0.025) * 0.875)
                expect(CGRect(x: 0, y: 0, width: side * 1.5, height: side).contains(motionBounds),
                       "\(name): shake cannot crop the silhouette")
            }

            let model = PetModel()
            model.apply(reading: BalanceReading(normalCny: 38.61, bonusCny: 0, spentCny: nil, raw: ""), snap: true)
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            let view = PetView(model: model, character: .deepseek)
            window.contentView = view
            var previous = PetCharacter.deepseek
            var previousPixels = renderedData(view)
            for next in [PetCharacter.gpt, .claude, .gemini, .deepseek] {
                let name = "\(Int(side))pt, \(previous.rawValue) → \(next.rawValue)"
                guard let before = fixtures[previous], let after = fixtures[next] else { continue }
                // A strong alpha difference avoids antialiasing thresholds and
                // proves that this very view updates its active hit-test mask.
                var changedPoint: CGPoint?
                for y in stride(from: 24, to: 1000, by: 24) {
                    for x in stride(from: 24, to: 1512, by: 24) {
                        guard let a = before.bitmap.colorAt(x: x, y: y)?.alphaComponent,
                              let b = after.bitmap.colorAt(x: x, y: y)?.alphaComponent else { continue }
                        if (a < 0.01 && b > 0.99) || (a > 0.99 && b < 0.01) {
                            changedPoint = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                            break
                        }
                    }
                    if changedPoint != nil { break }
                }
                let oldFrame = view.frame
                let previousHit = changedPoint.map { view.containsInteractivePoint(point($0)) }
                view.needsDisplay = false
                view.setCharacter(next)
                expect(view.character == next && view.needsDisplay && view.frame == oldFrame
                       && model.displayedCents == 3861,
                       "\(name): switching invalidates the same view and preserves geometry and balance")
                if let source = changedPoint, let oldHit = previousHit {
                    let nextHit = view.containsInteractivePoint(point(source))
                    expect(oldHit == before.sprite.isOpaque(at: normalized(source))
                           && nextHit == after.sprite.isOpaque(at: normalized(source)) && oldHit != nextHit,
                           "\(name): switching changes hit testing to the new silhouette")
                } else {
                    expect(false, "\(name): independent alpha difference is available for switching regression")
                }
                let actual = renderedData(view)
                let fresh = PetView(model: model, character: next)
                let expectedWindow = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                expectedWindow.contentView = fresh
                let expected = renderedData(fresh)
                expect(actual != nil && expected != nil && actual == expected && actual != previousPixels,
                       "\(name): switched drawing matches a fresh view of the selected character")
                previous = next
                previousPixels = actual
            }
        }

        offlineArtworkTests(expect)
        stateTests(expect)
        if let url = PetPaths.soundURL, let sound = NSSound(contentsOf: url, byReference: false) {
            expect(url.lastPathComponent == "hit.mp3" && sound.duration > 0, "original MP3 loads and decodes")
        } else { expect(false, "original MP3 loads and decodes") }
    }

    private static func offlineArtworkTests(_ expect: (Bool, String) -> Void) {
        guard let sprite = PetAssets.deepseekOffline else {
            expect(false, "offline bowl artwork loads")
            return
        }
        expect(sprite.image.width == 1536 && sprite.image.height == 1024,
               "offline artwork preserves supplied dimensions")
        for preset in PetController.sizePresets {
            let model = PetModel()
            let frame = CGRect(origin: .zero, size: PetLayout.windowSize(side: preset.side))
            let view = PetView(model: model)
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            let initial = renderedData(view)
            let imageOnly = ImageOnlyView(image: sprite.image, frame: frame)
            let referenceWindow = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            referenceWindow.contentView = imageOnly
            expect(initial != nil && initial == renderedData(imageOnly),
                   "offline rendering contains only supplied artwork, without any text or status dot")
            model.setNoCredential()
            expect(initial != nil && view.showsOfflineArtwork && renderedData(view) == initial,
                   "unconfigured and connecting blue pet show the same bowl artwork")
            let reading = BalanceReading(normalCny: 38.61, bonusCny: 0, spentCny: nil, raw: "")
            model.apply(reading: reading, snap: true)
            let online = renderedData(view)
            expect(!view.showsOfflineArtwork && online != initial,
                   "successful connection restores tablet artwork and balance")
            model.fail(.transport("offline fixture"))
            expect(view.showsOfflineArtwork && renderedData(view) == initial,
                   "connection failure hides stale balance and restores clean bowl artwork")
            let rect = PetLayout.spriteRect(in: frame)
            // Hit testing must use the bowl silhouette, not the former tablet.
            var maskMatches = true
            for y in stride(from: 32, to: 1024, by: 64) {
                for x in stride(from: 32, to: 1536, by: 64) {
                    let n = normalized(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
                    let point = CGPoint(x: rect.minX + n.x * rect.width, y: rect.minY + n.y * rect.height)
                    if view.containsInteractivePoint(point) != sprite.isOpaque(at: n) { maskMatches = false }
                }
            }
            expect(maskMatches, "offline hit testing follows the bowl image alpha")
            for character in [PetCharacter.gpt, .claude, .gemini] {
                view.setCharacter(character)
                expect(!view.showsOfflineArtwork && renderedData(view) != initial,
                       "other characters retain their artwork when offline")
            }
            view.setCharacter(.deepseek)
            model.apply(reading: reading, snap: true)
            expect(renderedData(view) == online, "reconnection restores identical normal rendering")
        }
    }

    private static func stateTests(_ expect: (Bool, String) -> Void) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-character-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        for character in PetCharacter.allCases {
            var state = PetState()
            state.character = character
            state.sizeIndex = 2
            state.soundOn = false
            state.save(to: url)
            let restored = PetState.load(from: url)
            expect(restored.character == character && restored.sizeIndex == 2 && !restored.soundOn,
                   "\(character.displayName): selection survives saving and loading settings")
        }
        for json in ["{\"sizeIndex\":2}", "{\"sizeIndex\":2,\"character\":\"unknown-future-character\"}"] {
            do {
                try Data(json.utf8).write(to: url)
                let restored = PetState.load(from: url)
                expect(restored.character == .deepseek && restored.sizeIndex == 2,
                       "legacy or unknown character settings preserve preferences and use the blue pet")
            } catch { expect(false, "character settings fixture can be written") }
        }
    }
}
