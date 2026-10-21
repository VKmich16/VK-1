import AppKit

/// Selected character artwork, with the readout mapped onto its tilted tablet.
/// The upper band is reserved for floating amounts and always passes clicks through.
final class PetView: NSView {
    weak var controller: PetController?
    let model: PetModel
    private(set) var character: PetCharacter
    var tariff: (today: Double, hourly: Double)?
    var mirrored = false
    var pat = PatGesture()
    private(set) var expression: PetExpression = .happy

    var showsOfflineArtwork: Bool { character == .deepseek && !model.connected }

    /// The whale uses full variants; other characters use localized face patches.
    private var activeSprite: PetAssets.Sprite? {
        if showsOfflineArtwork { return PetAssets.deepseekOffline }
        if character == .deepseek, let sprite = PetAssets.expressionSprite(expression) { return sprite }
        return PetAssets.sprite(for: character)
    }

    func setExpression(_ value: PetExpression) {
        guard value != expression else { return }
        expression = value
        needsDisplay = true
    }

    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var didDrag = false
    private(set) var isDragging = false

    init(model: PetModel, character: PetCharacter = .deepseek) {
        self.model = model
        self.character = character
        super.init(frame: NSRect(origin: .zero, size: PetLayout.windowSize(side: 150)))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("DSH 余额桌宠 · \(character.displayName)")
        setAccessibilityHelp("拖动以移动，右键打开菜单。余额也可在菜单栏查看。")
    }

    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    func setCharacter(_ character: PetCharacter) {
        self.character = character
        setAccessibilityLabel("DSH 余额桌宠 · \(character.displayName)")
        needsDisplay = true
    }

    // MARK: - Geometry and interaction

    /// A small inset keeps the original art, including its outermost pixels,
    /// inside the window even at the peak of the hurt shake.
    private var side: CGFloat { PetLayout.bodyHeight(in: bounds) }
    private var spriteRect: CGRect { PetLayout.spriteRect(in: bounds) }

    /// Artwork rect in the y-down virtual screen space used by the prop system.
    var spriteRectScreenDown: CGRect {
        guard let window = window else { return .zero }
        let rect = spriteRect
        let frame = window.frame
        return CGRect(x: frame.minX - ScreenSpace.union.minX + rect.minX,
                      y: ScreenSpace.top - (frame.minY + rect.maxY),
                      width: rect.width,
                      height: rect.height)
    }

    /// Silhouette used for bowl feeding. Always the character's normal art: the
    /// offline variant shows a different prop and would misalign the hit test.
    var solidBounds: CGRect {
        let a = (showsOfflineArtwork ? PetAssets.deepseekOffline : PetAssets.sprite(for: character))?.opaqueBounds ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        return CGRect(x: spriteRect.minX + (mirrored ? 1-a.maxX : a.minX) * spriteRect.width,
                      y: spriteRect.minY + a.minY * spriteRect.height,
                      width: a.width * spriteRect.width, height: a.height * spriteRect.height)
    }

    var hitSprite: PetAssets.Sprite? { PetAssets.sprite(for: character) ?? activeSprite }

    private var shakeOffset: CGPoint {
        guard model.shakeTime > 0 else { return .zero }
        let elapsed = model.hitDuration - model.shakeTime
        let decay = CGFloat(max(0, model.shakeTime / model.hitDuration))
        let amplitude = min(CGFloat(3.2), side * 0.025)
        return CGPoint(x: sin(elapsed * 24) * amplitude * decay,
                       y: cos(elapsed * 19) * amplitude * 0.875 * decay)
    }

    /// Used by both AppKit hit testing and the controller's window-level
    /// ignoresMouseEvents update. Returning nil from hitTest alone does not
    /// guarantee delivery to another application's window.
    func containsInteractivePoint(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        let offset = shakeOffset
        var local = CGPoint(x: point.x - offset.x, y: point.y - offset.y)
        let rect = spriteRect
        if controller?.props.hatContains(local, in: self) == true { return true }
        guard rect.contains(local) else { return false }
        if mirrored { local.x = 2*rect.midX-local.x }
        guard let sprite = activeSprite else { return true }
        return sprite.isOpaque(at: CGPoint(x: (local.x - rect.minX) / rect.width,
                                           y: (local.y - rect.minY) / rect.height))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview != nil ? convert(point, from: superview) : point
        return containsInteractivePoint(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            controller?.showContextMenu(with: event)
            return
        }
        // Double-clicking her head knocks the iron pot off, like the Windows build.
        if controller?.props.handleDoubleClick(at: ScreenSpace.down(window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation)) == true {
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        let panel = PetLayout.tabletTransform(in: bounds, character: character, mirrored: mirrored).inverted()
        if event.clickCount == 2, PetLayout.tabletBounds.contains(local.applying(panel)) {
            controller?.toggleTariff(); return
        }
        isDragging = true
        didDrag = false
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStartMouse.x
        let dy = now.y - dragStartMouse.y
        guard didDrag || hypot(dx, dy) >= 2 else { return }
        didDrag = true
        window.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        // A simple click should not unexpectedly move a manually placed pet.
        if didDrag { controller?.dragDidEnd() }
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.showContextMenu(with: event)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.saveGState()
        let offset = shakeOffset
        ctx.translateBy(x: offset.x, y: offset.y)
        if pat.active {
            let j = pat.phase
            ctx.translateBy(x: spriteRect.midX, y: spriteRect.minY)
            ctx.scaleBy(x: 1+0.015*j, y: 1-0.0625*j)
            ctx.translateBy(x: -spriteRect.midX, y: -spriteRect.minY)
        }

        if model.topupTime > 0 {
            let progress = 1 - CGFloat(model.topupTime / 0.9)
            let rect = spriteRect.insetBy(dx: side * (0.03 + 0.06 * (1 - progress)),
                                         dy: side * (0.03 + 0.06 * (1 - progress)))
            ctx.setStrokeColor(NSColor.systemGreen.withAlphaComponent(0.8 * (1 - progress)).cgColor)
            ctx.setLineWidth(side * 0.015)
            ctx.strokeEllipse(in: rect)
        }

        if let sprite = activeSprite {
            ctx.interpolationQuality = .high
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.saveGState()
            if mirrored { ctx.translateBy(x: bounds.width, y: 0); ctx.scaleBy(x: -1, y: 1) }
            ctx.draw(sprite.image, in: spriteRect)
            if let patch = PetAssets.facePatch(for: character, expression: expression) {
                let source = PetAssets.facePatchRect
                let rect = CGRect(x: spriteRect.minX+source.minX/1536*spriteRect.width,
                                  y: spriteRect.minY+(1024-source.maxY)/1024*spriteRect.height,
                                  width: source.width/1536*spriteRect.width,
                                  height: source.height/1024*spriteRect.height)
                ctx.draw(patch, in: rect)
            }
            ctx.restoreGState()
            controller?.props.maskCrown(ctx, in: self)
            if model.impact > 0 {
                // sourceAtop preserves the supplied sprite's alpha, including
                // its soft edge, instead of filling its transparent background.
                ctx.saveGState()
                ctx.setBlendMode(.sourceAtop)
                ctx.setFillColor(NSColor(srgbRed: 1, green: 0.10, blue: 0.14,
                                         alpha: 0.45 * model.impact).cgColor)
                ctx.fill(spriteRect)
                ctx.restoreGState()
            }
            ctx.endTransparencyLayer()
            if !showsOfflineArtwork { drawTabletText(ctx) }
        } else {
            // Keep the menu accessible if an installation loses its resources.
            NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: spriteRect, xRadius: 12, yRadius: 12).fill()
            drawCentered("缺少角色图片", font: .systemFont(ofSize: side * 0.08),
                         color: .labelColor, center: CGPoint(x: spriteRect.midX, y: spriteRect.midY))
        }
        controller?.props.drawHead(ctx, in: self)
        ctx.restoreGState()
        if !showsOfflineArtwork { drawFloating(ctx) }
        drawPat(ctx)
    }

    private func drawPat(_ ctx: CGContext) {
        guard pat.active, PetAssets.patHands.count == 5 else { return }
        let j = pat.phase
        let index = Int(j)
        let image = PetAssets.patHands[index]
        let w = side * 0.75, h = w * CGFloat(image.height) / CGFloat(image.width)
        let fx = mirrored ? 1-PetPropRules.headXFraction : PetPropRules.headXFraction
        let crown = CGPoint(x: spriteRect.midX+(spriteRect.minX+spriteRect.width*fx-spriteRect.midX)*(1+0.015*j),
                            y: spriteRect.minY+spriteRect.height*0.86*(1-0.0625*j))
        let palmX: [CGFloat] = [0.712, 0.749, 0.711, 0.818, 0.691]
        let palmY: [CGFloat] = [0.305, 0.514, 0.629, 0.538, 0.402]
        ctx.saveGState()
        ctx.translateBy(x: crown.x, y: crown.y)
        if mirrored { ctx.scaleBy(x: -1, y: 1) }
        ctx.draw(image, in: CGRect(x: -w*palmX[index], y: -h*(1-palmY[index]), width: w, height: h))
        ctx.restoreGState()
    }

    private func drawCentered(_ text: String, font: NSFont, color: NSColor, center: CGPoint) {
        let value = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = value.size()
        value.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }

    private func drawTabletText(_ ctx: CGContext) {
        let panelWidth = PetLayout.tabletBounds.width
        let panelHeight = PetLayout.tabletBounds.height
        ctx.saveGState()
        ctx.concatenate(PetLayout.tabletTransform(in: bounds, character: character, mirrored: mirrored))
        ctx.clip(to: PetLayout.tabletBounds)
        ctx.setShadow(offset: CGSize(width: 1.5, height: -1.5), blur: 1.5,
                      color: NSColor.black.withAlphaComponent(0.65).cgColor)

        let labelColor = NSColor(srgbRed: 0.62, green: 0.72, blue: 0.89, alpha: 1)
        drawCentered(tariff == nil ? "DSH 余额" : "今日观察消费", font: .systemFont(ofSize: panelHeight * 0.21, weight: .bold),
                     color: labelColor, center: CGPoint(x: panelWidth * 0.5, y: panelHeight * 0.80))

        // Fit long balances inside the tablet rather than clipping significant
        // digits. The currency sign stays smaller, matching the Windows version.
        let numberSize = panelHeight * 0.48
        let currencySize = panelHeight * 0.27
        func amount(_ factor: CGFloat) -> NSAttributedString {
            let value = NSMutableAttributedString(string: "¥ ", attributes: [
                .font: NSFont.systemFont(ofSize: currencySize * factor, weight: .bold),
                .foregroundColor: labelColor,
            ])
            value.append(NSAttributedString(string: tariff.map { String(format: "%.2f", $0.today) } ?? model.displayString, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: numberSize * factor, weight: .bold),
                .foregroundColor: model.connected ? NSColor(srgbRed: 0.94, green: 0.97, blue: 1, alpha: 1)
                                                  : NSColor(srgbRed: 0.68, green: 0.73, blue: 0.81, alpha: 1),
            ]))
            return value
        }
        let fullWidth = amount(1).size().width
        let value = amount(min(1, panelWidth * 0.90 / max(1, fullWidth)))
        let size = value.size()
        value.draw(at: CGPoint(x: (panelWidth - size.width) / 2,
                               y: panelHeight * 0.32 - size.height / 2))

        if let tariff = tariff {
            drawCentered(String(format: "最近 ¥%.2f / 小时", tariff.hourly),
                         font: .monospacedDigitSystemFont(ofSize: panelHeight*0.12, weight: .medium),
                         color: labelColor, center: CGPoint(x: panelWidth/2, y: panelHeight*0.10))
        }
        ctx.setShadow(offset: .zero, blur: 0)
        let statusColor: NSColor = model.connected ? .systemGreen
            : (model.lastError == nil ? .systemYellow : .systemRed)
        ctx.setFillColor(statusColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: panelWidth * 0.92, y: panelHeight * 0.77, width: 15, height: 15))
        ctx.restoreGState()
    }

    private func drawFloating(_ ctx: CGContext) {
        let start = side
        let top = bounds.height - side * 0.10
        let font = NSFont.monospacedDigitSystemFont(ofSize: side * 0.080, weight: .heavy)
        for label in model.floating {
            let progress = min(1, label.age / model.floatLifetime)
            let alpha = max(0, 1 - pow(progress, 1.6))
            let value = NSAttributedString(string: label.text, attributes: [
                .font: font, .foregroundColor: label.color.withAlphaComponent(alpha),
            ])
            let size = value.size()
            // Follow the character on the right, rather than centering over the tail.
            let anchorX = mirrored ? side*(1-label.x) : bounds.width-side+side*label.x
            let x = min(max(0, anchorX - size.width / 2),
                        max(0, bounds.width - size.width))
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: side * 0.022,
                          color: NSColor.black.withAlphaComponent(0.4 * alpha).cgColor)
            value.draw(at: CGPoint(x: x, y: start + (top - start) * CGFloat(progress)))
            ctx.restoreGState()
        }
    }
}

final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
