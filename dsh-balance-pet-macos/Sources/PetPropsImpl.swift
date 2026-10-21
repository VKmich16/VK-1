import AppKit

// MARK: - Shared screen space

/// The Windows build paints into one virtual-desktop canvas whose y axis points
/// down from the top. macOS windows use a bottom-left origin, so every prop
/// calculation is done in that y-down space and converted only when placing a
/// window. This keeps the upstream formulas readable.
enum ScreenSpace {
    private(set) static var union = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private(set) static var workAreas: [CGRect] = [union]
    static var top: CGFloat { union.maxY }
    static var height: CGFloat { max(1, union.height) }
    static var width: CGFloat { max(1, union.width) }

    static func refresh() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        configure(frames: screens.map(\.frame), visible: screens.map(\.visibleFrame))
    }
    static func configure(frames: [CGRect], visible: [CGRect]) {
        guard let first = frames.first, frames.count == visible.count else { return }
        union = frames.dropFirst().reduce(first) { $0.union($1) }
        workAreas = visible.map { f in
            CGRect(x: f.minX-union.minX, y: top-f.maxY, width: f.width, height: f.height)
        }
    }

    static func down(_ p: NSPoint) -> CGPoint {
        CGPoint(x: p.x - union.minX, y: top - p.y)
    }
    static func up(_ p: CGPoint) -> NSPoint {
        NSPoint(x: p.x + union.minX, y: top - p.y)
    }
    static func area(at p: CGPoint) -> CGRect {
        workAreas.min {
            distance(p, to: $0) < distance(p, to: $1)
        } ?? CGRect(x: 0, y: 0, width: width, height: height)
    }
    private static func distance(_ p: CGPoint, to r: CGRect) -> CGFloat {
        hypot(max(r.minX-p.x, 0, p.x-r.maxX), max(r.minY-p.y, 0, p.y-r.maxY))
    }
}

// MARK: - Sound cues

enum PetSound: String, CaseIterable {
    case hit, feed, potLand, potOff

    var file: String {
        switch self {
        case .hit: return "hit"
        case .feed: return "feed"
        case .potLand: return "pot_land"
        case .potOff: return "pot_off"
        }
    }

    /// Concurrent voices, matching the Windows pool sizes (4 / 2 / 2 / 2).
    var voices: Int { self == .hit ? 4 : 2 }
}

/// A small round-robin pool so repeated cues overlap instead of cutting each
/// other off, matching the Windows build's per-cue MCI slots.
final class SoundBank {
    private var pools: [PetSound: [NSSound]] = [:]
    private var cursors: [PetSound: Int] = [:]
    var enabled = true { didSet { if !enabled { pools.values.flatMap { $0 }.forEach { $0.stop() } } } }
    var volumes: [Float] = [0.8, 0.8, 0.8, 0.8]
    private func volume(_ cue: PetSound) -> Float {
        let i = PetSound.allCases.firstIndex(of: cue) ?? 0
        return volumes.indices.contains(i) ? min(1, max(0, volumes[i])) : 0.8
    }

    func preload() {
        pools.values.flatMap { $0 }.forEach { $0.stop() }
        for sound in PetSound.allCases {
            var players: [NSSound] = []
            if let url = Self.url(for: sound) {
                for _ in 0..<sound.voices {
                    if let player = NSSound(contentsOf: url, byReference: true) {
                        player.volume = volume(sound)
                        players.append(player)
                    }
                }
            } else {
                Log.write("sound \(sound.file).mp3 is missing")
            }
            pools[sound] = players
        }
    }

    func play(_ sound: PetSound) {
        guard enabled, let players = pools[sound], !players.isEmpty else { return }
        let index = (cursors[sound] ?? 0) % players.count
        cursors[sound] = index + 1
        let player = players[index]
        player.stop()
        player.volume = volume(sound)
        player.play()
    }

    static func customURL(for sound: PetSound) -> URL {
        PetPaths.support.appendingPathComponent("soundfx").appendingPathComponent(sound.file+".audio")
    }

    static func url(for sound: PetSound) -> URL? {
        let custom = customURL(for: sound)
        if FileManager.default.fileExists(atPath: custom.path) { return custom }
        if let bundled = Bundle.main.url(forResource: sound.file, withExtension: "mp3") {
            return bundled
        }
        let candidates = [PetPaths.executableDir, PetPaths.support].map {
            $0.appendingPathComponent(sound.file + ".mp3")
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

// MARK: - Constants ported from the Windows build

enum PetPropRules {
    static let gravity: CGFloat = 2100
    static let restitution: CGFloat = 0.5
    static let airDrag: CGFloat = 0.30
    static let slideFriction: CGFloat = 1.40
    static let slideStop: CGFloat = 14
    static let maxBounces = 3
    static let minBounceImpact: CGFloat = 90
    static let restSpeed: CGFloat = 45

    static let bowlLockSeconds: Double = 10
    static let suckAccel: CGFloat = 960
    static let suckMaxSpeed: CGFloat = 2400
    static let suckDelay: Double = 1.0

    static let feedFade: Double = 0.14
    static let potFade: Double = 0.45
    static let ironTiltDeg: CGFloat = 6.23

    // Measured on the 1536x1024 mac artwork (headdress centre x = 1104/1536,
    // fitted rim y = 340/1024); the upstream constants were measured on the
    // 1024-wide Windows canvas and land too far left/low here.
    static let headXFraction: CGFloat = 1104.0 / 1536.0
    static let headRimFraction: CGFloat = 340.0 / 1024.0
    static let headBoxHalfW: CGFloat = 0.26
    static let headBoxHalfH: CGFloat = 0.18
    static let knockXFraction: CGFloat = 0.47
    static let knockYFraction: CGFloat = 0.30
    static let knockInterval: TimeInterval = 0.4
    static let knockSlop: CGFloat = 24

    static let riceArtFraction: CGFloat = 0.44
    static let ironArtFraction: CGFloat = 0.66
    static let footprintFraction: CGFloat = 0.42
    static let stackGap: CGFloat = 2.0 / 3.0
    static let radarFraction: CGFloat = 1.33 * 2 * 0.42
    static let plateThreshold: CGFloat = 24
    static let radarGreen = NSColor(srgbRed: 0, green: 1, blue: 8.0 / 255.0, alpha: 1)
    static let radarShadow = NSColor(srgbRed: 0, green: 40.0 / 255.0, blue: 0, alpha: 170.0 / 255.0)
}

// MARK: - Prop model

final class PetProp {
    enum Kind { case rice, iron }

    let kind: Kind
    var x: CGFloat              // centre, screen points, y down from the virtual top
    var y: CGFloat
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var cents: Int = 0
    var amount: Double { Double(cents) / 100 }
    var radius: CGFloat
    var artSize: CGSize
    var isTest = false

    var hasLanded = false
    var waitTime: Double = 0
    var grounded = false
    var dragging = false
    var fed = false
    var dieT: Double = 0
    var bounces = 0
    var maxBounces = PetPropRules.maxBounces
    var squish: CGFloat = 0
    var squishT: Double = 0
    var squishDur: Double = 0.4

    var onHead = false
    var headSlot = 0
    var headFadeT: Double = 0

    var beingSucked = false
    var suckSpeed: CGFloat = 0

    var grabDX: CGFloat = 0
    var grabDY: CGFloat = 0
    var plate = RadarPlate.empty
    var loggedLanding = false

    var window: PropWindow!
    var view: PropView!

    init(kind: Kind, x: CGFloat, y: CGFloat, radius: CGFloat, artSize: CGSize) {
        self.kind = kind
        self.x = x
        self.y = y
        self.radius = radius
        self.artSize = artSize
    }

    var isGone: Bool {
        (fed && dieT >= PetPropRules.feedFade) || headFadeT >= PetPropRules.potFade
    }
}

// MARK: - Radar plate

struct RadarPlate {
    var on = false
    var locked = false
    var distText = "--"
    var closureText = "--"
    var altText = "--"
    var dirDeg: CGFloat = 0
    var s: CGFloat = 0
    static let empty = RadarPlate()
}

// MARK: - Views

final class PropWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Tight window around a bowl or pot. Keeping it small means a hovered prop
/// never blocks clicks over a large transparent frame.
final class PropView: NSView {
    weak var prop: PetProp?
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?

    // NOT flipped: CGContext.draw(CGImage) mirrors bitmaps in a flipped view,
    // which made the rice bowl fall upside down. The artwork is drawn centred,
    // so the view only needs the standard bottom-left origin.
    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(event) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(event) }

    override func draw(_ dirtyRect: NSRect) {
        guard let prop = prop, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        let art = prop.kind == .rice ? PetAssets.riceArt : PetAssets.ironArt
        guard let image = art else { return }
        var sx: CGFloat = 1, sy: CGFloat = 1
        if prop.squish != 0 {
            sx = max(0.15, 1 + 0.75 * prop.squish)
            sy = max(0.15, 1 - 0.75 * prop.squish)
        }
        let w = prop.artSize.width * sx
        let h = prop.artSize.height * sy
        ctx.saveGState()
        // A resting bowl is anchored by its bottom edge at y + R, exactly like
        // the Windows build; a worn pot is anchored by its centre on the head.
        if prop.onHead {
            ctx.translateBy(x: bounds.midX, y: bounds.midY)
            ctx.rotate(by: -PetPropRules.ironTiltDeg * .pi / 180)
        } else {
            ctx.translateBy(x: bounds.midX, y: bounds.midY - prop.radius + h / 2)
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        ctx.restoreGState()
    }
}

/// Screen-sized, click-through layer carrying every radar plate. The Windows
/// build paints plates after the bowls in one canvas; a dedicated input-free
/// overlay gives the same stacking without a full-screen input window.
final class RadarOverlayView: NSView {
    var plates: [(centre: CGPoint, plate: RadarPlate)] = []
    private(set) var drawnReadoutRects: [CGRect] = []

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        drawnReadoutRects.removeAll(keepingCapacity: true)
        for entry in plates where entry.plate.on && entry.plate.s >= PetPropRules.plateThreshold {
            drawPlate(entry.plate, at: entry.centre)
        }
    }

    private func drawPlate(_ plate: RadarPlate, at centre: CGPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = plate.s
        let cx = min(bounds.maxX-s/2-1, max(bounds.minX+s/2+1, centre.x))
        let cy = min(bounds.maxY-s/2-1, max(bounds.minY+s/2+1, centre.y))
        let x0 = cx - s / 2, y0 = cy - s / 2, x1 = cx + s / 2, y1 = cy + s / 2
        let stroke = max(2, 0.075 * s)
        let len = 0.30 * s

        ctx.setFillColor(PetPropRules.radarGreen.cgColor)
        for arm in [
            CGRect(x: x0, y: y0, width: len, height: stroke),
            CGRect(x: x1 - len, y: y0, width: len, height: stroke),
            CGRect(x: x0, y: y1 - stroke, width: len, height: stroke),
            CGRect(x: x1 - len, y: y1 - stroke, width: len, height: stroke),
            CGRect(x: x0, y: y0, width: stroke, height: len),
            CGRect(x: x1 - stroke, y: y0, width: stroke, height: len),
            CGRect(x: x0, y: y1 - len, width: stroke, height: len),
            CGRect(x: x1 - stroke, y: y1 - len, width: stroke, height: len),
        ] {
            ctx.fill(arm)
        }

        let typeH = max(9, 0.18 * s)
        let numH = max(9, 0.16 * s)
        let gap = 0.08 * s

        let type = Self.label(plate.locked ? "白饭 · 锁定" : "白饭", height: typeH, mono: false)
        drawLabel(type, at: CGPoint(x: cx-type.size().width/2, y: y0-type.size().height-0.06*s))

        let labels = [Self.label(plate.distText, height: numH, mono: true),
                      Self.label(plate.closureText, height: numH, mono: true),
                      Self.label(plate.altText, height: numH, mono: true)]
        let columnW = labels.map { $0.size().width }.max() ?? 0
        let x = x1+gap+columnW <= bounds.maxX-2 ? x1+gap : x0-gap-columnW
        let columnH = labels.reduce(CGFloat(0)) { $0+$1.size().height }+2*gap
        var rowY = max(bounds.minY+2, min(y0, bounds.maxY-columnH-2))
        for label in labels {
            drawLabel(label, at: CGPoint(x: x, y: rowY))
            rowY += label.size().height+gap
        }

        let ringR = 0.185 * s
        let ringW = 0.075 * s
        let reach = ringR+0.15*s+ringW
        var rcx = cx, rcy = y1+0.70*s
        if rcy+reach > bounds.maxY {
            rcx = x > cx ? x0-reach-gap : x1+reach+gap
            rcy = cy
            if rcx-reach < bounds.minX || rcx+reach > bounds.maxX {
                rcx = cx
                rcy = y0-type.size().height-2*gap-reach
            }
        }
        rcx = max(bounds.minX+reach, min(bounds.maxX-reach, rcx))
        rcy = max(bounds.minY+reach, min(bounds.maxY-reach, rcy))
        drawnReadoutRects.append(CGRect(x: rcx-reach, y: rcy-reach, width: reach*2, height: reach*2))
        ctx.setStrokeColor(PetPropRules.radarGreen.cgColor)
        ctx.setLineWidth(ringW)
        ctx.strokeEllipse(in: CGRect(x: rcx - ringR + ringW / 2, y: rcy - ringR + ringW / 2,
                                     width: (ringR - ringW / 2) * 2,
                                     height: (ringR - ringW / 2) * 2))
        let ang = plate.dirDeg * .pi / 180
        ctx.setLineCap(.square)
        ctx.move(to: CGPoint(x: rcx + cos(ang) * (ringR + ringW * 0.5),
                             y: rcy + sin(ang) * (ringR + ringW * 0.5)))
        ctx.addLine(to: CGPoint(x: rcx + cos(ang) * (ringR + 0.15 * s),
                                y: rcy + sin(ang) * (ringR + 0.15 * s)))
        ctx.strokePath()
    }

    private func drawLabel(_ label: NSAttributedString, at proposed: CGPoint) {
        let size = label.size()
        let point = CGPoint(x: max(bounds.minX+2, min(bounds.maxX-size.width-2, proposed.x)),
                            y: max(bounds.minY+2, min(bounds.maxY-size.height-2, proposed.y)))
        drawnReadoutRects.append(CGRect(origin: point, size: size))
        label.draw(at: point)
    }

    private static func label(_ text: String, height: CGFloat, mono: Bool) -> NSAttributedString {
        let size = max(9, height * 1.38)
        let font: NSFont = mono
            ? .monospacedDigitSystemFont(ofSize: size, weight: .bold)
            : .systemFont(ofSize: size, weight: .bold)
        let value = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: PetPropRules.radarGreen,
        ])
        let shadow = NSShadow()
        shadow.shadowColor = PetPropRules.radarShadow
        shadow.shadowOffset = NSSize(width: 1, height: 1)
        shadow.shadowBlurRadius = 0
        value.addAttribute(.shadow, value: shadow, range: NSRange(location: 0, length: value.length))
        return value
    }
}

final class RadarWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Prop system

/// Owns recharge bowls, iron pots, their windows and the radar overlay. All
/// model geometry is in screen points with y pointing down from the virtual top.
final class PropSystem {
    weak var controller: PetController?

    private(set) var props: [PetProp] = []
    static let maxProps = 32
    private var radars: [ObjectIdentifier: (window: RadarWindow, view: RadarOverlayView)] = [:]
    private let visible: Bool
    init(visible: Bool = true) { self.visible = visible }

    var petRef: () -> CGPoint = { .zero }
    var headRim: () -> CGPoint = { .zero }
    var knockCentre: () -> CGPoint = { .zero }
    var ownerWindow: (() -> NSWindow?) = { nil }
    var isMenuTracking = false
    var artHeight: () -> CGFloat = { 150 }
    var petSolid: (CGPoint) -> Bool = { _ in false }
    var petBounds: () -> CGRect = { .zero }
    var onFeed: (Int, Bool) -> Void = { _, _ in }
    var onSound: (PetSound) -> Void = { _ in }

    private var bowlWait: Double = 0
    private var lockAll = false
    private var lockTimer: Double = 0
    private var lastKnockTime: TimeInterval = -100
    private var lastKnockPoint = CGPoint.zero
    private var dragSamples: [(time: TimeInterval, point: CGPoint)] = []

    var isEmpty: Bool { props.isEmpty }
    var hasBowls: Bool { props.contains { $0.kind == .rice && !$0.fed } }
    var hasPotOnHead: Bool { props.contains { $0.onHead && $0.kind == .iron && !$0.isGone } }
    var waitingSeconds: Double { bowlWait }

    // MARK: Art

    func artSizes(side: CGFloat) -> (rice: CGSize, iron: CGSize) {
        let rw = max(24, (side * PetPropRules.riceArtFraction).rounded())
        let iw = max(24, (side * PetPropRules.ironArtFraction).rounded())
        let base = PetAssets.ironArtBaseSize
        let aspect = base.width > 1 ? base.height / base.width : 0.355
        return (CGSize(width: rw, height: rw), CGSize(width: iw, height: max(8, (iw * aspect).rounded())))
    }

    func appKitOrigin(centre: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: centre.x + ScreenSpace.union.minX - size.width / 2,
                y: ScreenSpace.top - (centre.y + size.height / 2))
    }

    // MARK: Spawning

    func spawnRice(amount: Double, test: Bool = false) {
        guard amount.isFinite, amount > 0, amount < 1e12 else { return }
        spawnRice(cents: Int((amount * 100).rounded()), test: test)
    }

    func spawnRice(cents: Int, test: Bool = false) {
        guard cents > 0 else { return }
        if props.count >= Self.maxProps {
            // Never lose a real credit when the user fills the desktop with demos.
            onFeed(cents, test)
            return
        }
        let side = controller?.side ?? 150
        let sizes = artSizes(side: side)
        let r = sizes.rice.width * PetPropRules.footprintFraction
        let n = CGFloat(props.filter { $0.kind == .rice && !$0.fed }.count)
        let area = ScreenSpace.area(at: petRef())
        let prop = PetProp(kind: .rice,
                           x: max(area.minX + r, area.maxX - r * 1.2 - n * r * 0.5),
                           y: area.minY - r * 1.2,
                           radius: r,
                           artSize: sizes.rice)
        if controller?.view?.mirrored == true { prop.x = min(area.maxX-r, area.minX+r*1.2+n*r*0.5) }
        prop.cents = cents
        prop.isTest = test
        prop.vx = (controller?.view?.mirrored == true) ? 120 : -120
        prop.vy = 40
        add(prop)
        Log.write(String(format: "credit %.2f -> rice bowl (test %@)", prop.amount, test ? "yes" : "no"))
    }

    /// Diagnostic helper: drop a pot from above her head so the seating path runs.
    func spawnIronAboveHead() {
        guard props.count < Self.maxProps else { return }
        let side = controller?.side ?? 150
        let sizes = artSizes(side: side)
        let head = headRim()
        let prop = PetProp(kind: .iron, x: head.x, y: head.y - sizes.iron.height,
                           radius: sizes.iron.height / 2,
                           artSize: sizes.iron)
        prop.vy = 120
        add(prop)
        Log.write(String(format: "pot test: spawned above head at (%.0f, %.0f)", prop.x, prop.y))
    }

    func spawnIron(at bowl: PetProp) {
        guard props.count < Self.maxProps else { return }
        let side = controller?.side ?? 150
        let sizes = artSizes(side: side)
        let prop = PetProp(kind: .iron, x: bowl.x, y: bowl.y,
                           radius: sizes.iron.height / 2,
                           artSize: sizes.iron)
        add(prop)
        Log.write(String(format: "iron pot spawned at (%.0f, %.0f)", prop.x, prop.y))
    }

    private func add(_ prop: PetProp) {
        let margin: CGFloat = 8
        // A resting prop is anchored by its bottom edge at y + R, which can sit
        // outside an art-sized box; size the window to the drawn extent instead.
        let halfW = prop.artSize.width / 2 + margin
        let halfH = max(prop.radius, prop.artSize.height - prop.radius) + margin
        let size = CGSize(width: halfW * 2, height: halfH * 2)
        let window = PropWindow(contentRect: CGRect(origin: appKitOrigin(centre: CGPoint(x: prop.x, y: prop.y), size: size),
                                                    size: size),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true
        let view = PropView(frame: CGRect(origin: .zero, size: size))
        view.prop = prop
        view.onMouseDown = { [weak self, weak prop] _ in if let prop = prop { self?.mouseDown(prop) } }
        view.onMouseDragged = { [weak self, weak prop] _ in if let prop = prop { self?.mouseDragged(prop) } }
        view.onMouseUp = { [weak self, weak prop] _ in if let prop = prop { self?.mouseUp(prop) } }
        window.contentView = view
        if visible { window.orderFrontRegardless() }
        prop.window = window
        prop.view = view
        props.append(prop)
    }

    func remove(_ prop: PetProp) {
        prop.window?.orderOut(nil)
        prop.window?.close()
        prop.window?.contentView = nil
        prop.window = nil
        prop.view = nil
        props.removeAll { $0 === prop }
        if props.isEmpty { hideRadar() }
        controller?.updateHatSpace()
    }

    func removeAll() {
        for prop in Array(props) { remove(prop) }
        props.removeAll()
        hideRadar()
        bowlWait = 0
        lockAll = false
        lockTimer = 0
    }

    // MARK: Tick

    func tick(_ dt: Double, cursor: CGPoint) {
        guard !props.isEmpty else { return }
        guard dt.isFinite else { return }
        let step = min(0.05, max(0, dt))
        updateWait(step)
        updateLock(step)
        let hadHat = hasPotOnHead
        for prop in Array(props) { update(prop, step) }
        collide()
        for prop in props where !prop.onHead && !prop.dragging { confine(prop) }
        if hadHat != hasPotOnHead || props.contains(where: { $0.headFadeT > 0 }) { controller?.view?.needsDisplay = true }
        if lockAll && lockTimer >= PetPropRules.suckDelay { suck(step) }
        layout()
        updateMouseRouting(cursor)
        updateRadarOverlay()
    }

    private func updateWait(_ dt: Double) {
        // Each bowl owns its wait clock; time before a later bowl arrived is not inherited.
        for prop in props where prop.kind == .rice && !prop.fed && prop.hasLanded && !lockAll {
            prop.waitTime += dt
        }
        bowlWait = props.filter { $0.kind == .rice && !$0.fed }.map(\.waitTime).max() ?? 0
        if bowlWait >= PetPropRules.bowlLockSeconds, !lockAll {
            lockAll = true
            lockTimer = 0
        }
    }

    private func updateLock(_ dt: Double) {
        guard hasBowls else {
            lockAll = false
                lockTimer = 0
            return
        }
        for prop in props where prop.kind == .rice && !prop.fed {
            prop.plate = plate(for: prop)
            prop.plate.on = true
            prop.plate.locked = lockAll
        }
        if lockAll { lockTimer += dt }
    }

    private func update(_ prop: PetProp, _ dt: Double) {
        if prop.fed {
            prop.dieT += dt
            if prop.isGone { remove(prop) }
            return
        }
        if prop.onHead {
            // headFadeT only runs after a knock; a worn pot stays indefinitely.
            if prop.headFadeT > 0 {
                prop.headFadeT += dt
                if prop.isGone { remove(prop); return }
            }
            positionOnHead(prop)
            return
        }
        if prop.dragging {
            if prop.kind == .rice, onGirl(prop) { feed(prop) }
            return
        }
        if prop.beingSucked { return }
        if prop.grounded && prop.squish == 0 { return }

        prop.vy += PetPropRules.gravity * dt
        prop.vx *= max(0, 1 - PetPropRules.airDrag * dt)
        prop.x += prop.vx * dt
        prop.y += prop.vy * dt

        let area = ScreenSpace.area(at: CGPoint(x: prop.x, y: prop.y))
        let floor = area.maxY - prop.radius
        if prop.y >= floor {
            prop.hasLanded = true
            prop.y = floor
            let impact = prop.vy
            let sliding = abs(prop.vx) > PetPropRules.slideStop
            if sliding { prop.vx *= 0.92 }
            prop.vy = -impact * PetPropRules.restitution
            if impact > PetPropRules.minBounceImpact, prop.bounces < prop.maxBounces {
                prop.bounces += 1
                prop.squish = 1
                prop.squishT = 0
                prop.squishDur = 0.40
            }
            if prop.bounces >= prop.maxBounces || abs(prop.vy) < PetPropRules.restSpeed {
                prop.vy = 0
                prop.grounded = !sliding
                if !sliding { prop.vx = 0 }
            }
        } else if prop.y >= floor - 0.5, abs(prop.vy) < PetPropRules.restSpeed {
            prop.vx *= max(0, 1 - PetPropRules.slideFriction * dt)
            if abs(prop.vx) <= PetPropRules.slideStop {
                prop.vx = 0
                prop.grounded = true
            }
        }

        if prop.x < area.minX + prop.artSize.width / 2 {
            prop.x = area.minX + prop.artSize.width / 2
            prop.vx = abs(prop.vx) * 0.5
        } else if prop.x > area.maxX - prop.artSize.width / 2 {
            prop.x = area.maxX - prop.artSize.width / 2
            prop.vx = -abs(prop.vx) * 0.5
        }
        if prop.y < area.minY + prop.artSize.height - prop.radius {
            prop.y = area.minY + prop.artSize.height - prop.radius
            if prop.vy < 0 { prop.vy = 0 }
        }

        if prop.squishT < prop.squishDur {
            prop.squishT += dt
            let u = prop.squishT / prop.squishDur
            prop.squish = CGFloat(cos(u * 2 * .pi * 2.2)) * CGFloat(1 - u) * 0.52
            if prop.squishT >= prop.squishDur { prop.squish = 0 }
        }

        if prop.kind == .iron, prop.vy > 30 {
            if let slot = stackSlot(prop) ?? headSlot(prop) {
                attachPot(prop, slot: slot)
                return
            }
        }

        if !prop.loggedLanding, prop.grounded, prop.kind == .rice {
            prop.loggedLanding = true
            Log.write(String(format: "bowl landed at (%.0f, %.0f)", prop.x, prop.y))
        }

        if prop.kind == .rice, onGirl(prop) { feed(prop) }
    }

    private func collide() {
        guard props.count > 1 else { return }
        let movable = props.filter { !$0.onHead && !$0.fed && !$0.dragging }
        guard movable.count > 1 else { return }
        for i in 0..<(movable.count - 1) {
            for j in (i + 1)..<movable.count {
                let a = movable[i], b = movable[j]
                let dx = b.x - a.x, dy = b.y - a.y
                let dist = max(0.001, hypot(dx, dy))
                let ea = sqrt(a.artSize.width * a.artSize.height) / 2
                let eb = sqrt(b.artSize.width * b.artSize.height) / 2
                let minD = ea + eb
                guard dist < minD else { continue }
                let ux: CGFloat = dist <= 0.001 ? 1 : dx / dist
                let uy: CGFloat = dist <= 0.001 ? 0 : dy / dist
                let push = (minD - dist) / 2
                a.x -= ux * push; a.y -= uy * push
                b.x += ux * push; b.y += uy * push
                a.grounded = false; b.grounded = false
                let rel = (b.vx - a.vx) * ux + (b.vy - a.vy) * uy
                guard rel < 0 else { continue }
                let impulse = -rel * 0.45
                a.vx -= impulse * ux; a.vy -= impulse * uy
                b.vx += impulse * ux; b.vy += impulse * uy
                a.grounded = false; b.grounded = false
            }
        }
    }

    private func suck(_ dt: Double) {
        let target = petRef()
        for prop in props where prop.kind == .rice && !prop.fed && !prop.dragging {
            guard prop.plate.on else { continue }
            prop.beingSucked = true
            prop.grounded = false
            prop.suckSpeed = min(PetPropRules.suckMaxSpeed, prop.suckSpeed + PetPropRules.suckAccel * CGFloat(dt))
            let dx = target.x - prop.x, dy = target.y - prop.y
            let dist = max(0.001, hypot(dx, dy))
            let stepLen = prop.suckSpeed * CGFloat(dt)
            if stepLen >= dist {
                prop.x = target.x; prop.y = target.y
            } else {
                prop.x += dx / dist * stepLen
                prop.y += dy / dist * stepLen
            }
            prop.vx = dx / dist * prop.suckSpeed
            prop.vy = dy / dist * prop.suckSpeed
            if onGirl(prop) {
                Log.write(String(format: "bowl reached girl at (%.0f, %.0f)", prop.x, prop.y))
                feed(prop)
            }
        }
    }

    private func feed(_ prop: PetProp) {
        guard !prop.fed else { return }
        prop.fed = true
        prop.dieT = 0
        prop.beingSucked = false
        prop.dragging = false
        onFeed(prop.cents, prop.isTest)
        spawnIron(at: prop)
    }

    // MARK: Hit tests

    private func onGirl(_ prop: PetProp) -> Bool {
        let rect = petBounds()
        let r = prop.artSize.width * 0.5 * 0.45
        guard rect.intersects(CGRect(x: prop.x-r, y: prop.y-r, width: 2*r, height: 2*r)) else { return false }
        let need = max(3, Int((r * 0.35).rounded()))
        var hits = 0
        var dy = -r
        while dy <= r {
            var dx = -r
            while dx <= r {
                if dx * dx + dy * dy <= r * r, petSolid(CGPoint(x: prop.x + dx, y: prop.y + dy)) {
                    hits += 1
                    if hits >= need { return true }
                }
                dx += 2
            }
            dy += 2
        }
        return false
    }

    func grabRadius(_ prop: PetProp) -> CGFloat { prop.artSize.width * 0.72 / 2 }

    func bowl(at point: CGPoint) -> PetProp? {
        for prop in props.reversed() where !prop.fed && !prop.onHead {
            let bottom = prop.y + prop.radius
            let box = CGRect(x: prop.x-prop.artSize.width/2, y: bottom-prop.artSize.height,
                             width: prop.artSize.width, height: prop.artSize.height).insetBy(dx: -3, dy: -3)
            if box.contains(point) { return prop }
        }
        return nil
    }

    // MARK: Drag

    private func mouseDown(_ prop: PetProp) { beginDrag(prop, at: ScreenSpace.down(NSEvent.mouseLocation)) }

    func beginDrag(_ prop: PetProp, at point: CGPoint) {
        guard !prop.fed, !prop.onHead else { return }
        prop.dragging = true
        prop.grounded = false
        prop.bounces = 0
        prop.beingSucked = false
        prop.grabDX = point.x - prop.x
        prop.grabDY = point.y - prop.y
        prop.vx = 0; prop.vy = 0
        dragSamples = [(ProcessInfo.processInfo.systemUptime, point)]
    }

    private func mouseDragged(_ prop: PetProp) { drag(prop, to: ScreenSpace.down(NSEvent.mouseLocation)) }

    func drag(_ prop: PetProp, to point: CGPoint) {
        guard prop.dragging else { return }
        prop.x = point.x - prop.grabDX
        prop.y = point.y - prop.grabDY
        confine(prop)
        dragSamples.append((ProcessInfo.processInfo.systemUptime, point))
        if dragSamples.count > 12 { dragSamples.removeFirst() }
        if let first = dragSamples.first, let last = dragSamples.last, last.time > first.time {
            let dt = CGFloat(last.time-first.time)
            prop.vx = max(-4200, min(4200, (last.point.x-first.point.x)/dt))
            prop.vy = max(-1700, min(1700, (last.point.y-first.point.y)/dt))
        }
        if prop.kind == .rice, onGirl(prop) { feed(prop) }
        layout()
    }

    private func mouseUp(_ prop: PetProp) { endDrag(prop) }

    func endDrag(_ prop: PetProp) {
        guard prop.dragging else { return }
        prop.dragging = false
        var vx: CGFloat = 0, vy: CGFloat = 0
        let recent = dragSamples.filter { ProcessInfo.processInfo.systemUptime - $0.time < 0.15 }
        if let first = recent.first, let last = recent.last, recent.count >= 2 {
            let dt = max(0.001, last.time - first.time)
            vx = (last.point.x - first.point.x) / CGFloat(dt)
            vy = (last.point.y - first.point.y) / CGFloat(dt)
        }
        dragSamples.removeAll()
        prop.vx = max(-4200, min(4200, vx))
        prop.vy = max(-1700, min(1700, vy))
        if hypot(prop.vx, prop.vy) < 12 { prop.vx = 0; prop.vy = 0 }
        let drop = max(0, ScreenSpace.area(at: CGPoint(x: prop.x, y: prop.y)).maxY-prop.radius-prop.y)
        prop.maxBounces = drop < 60 ? 0 : (drop < 260 ? 1 : (drop < 700 ? 2 : 3))
        if prop.kind == .rice, onGirl(prop) { feed(prop) }
        if prop.kind == .iron, let slot = stackSlot(prop) ?? headSlot(prop) { attachPot(prop, slot: slot) }
    }

    // MARK: Iron pot seating

    private func headSlot(_ prop: PetProp) -> Int? {
        let centre = headRim()
        let h = artHeight()
        let rimX = prop.x
        let rimY = prop.y + prop.artSize.height / 2
        guard abs(rimX - centre.x) < h * PetPropRules.headBoxHalfW,
              abs(rimY - centre.y) < h * PetPropRules.headBoxHalfH else { return nil }
        return 0
    }

    private func stackSlot(_ prop: PetProp) -> Int? {
        let stacked = props.filter { $0.onHead && $0.kind == .iron && $0.headFadeT == 0 }
        guard let top = stacked.max(by: { $0.headSlot < $1.headSlot }) else { return nil }
        let topRim = top.y - top.artSize.height / 2
        let rimY = prop.y + prop.artSize.height / 2
        guard rimY >= topRim - 14, rimY <= topRim + top.artSize.height,
              abs(prop.x - top.x) <= prop.artSize.width / 2 else { return nil }
        return top.headSlot + 1
    }

    func attachPot(_ prop: PetProp, slot: Int) {
        prop.onHead = true
        prop.window?.orderOut(nil)
        controller?.model.flinchForPot()
        prop.headSlot = slot
        // A pot seated on the head must not keep the squash from its fall.
        prop.squish = 0
        prop.squishT = prop.squishDur
        prop.beingSucked = false
        prop.dragging = false
        prop.vx = 0; prop.vy = 0
        prop.grounded = false
        onSound(.potLand)
        positionOnHead(prop)
        controller?.updateHatSpace()
        controller?.view?.needsDisplay = true
        Log.write("iron pot seated on head (slot \(slot))")
    }

    private func stackOffset(slot: Int, height h: CGFloat) -> CGFloat {
        let topSlot = max(slot, props.filter { $0.onHead }.map(\.headSlot).max() ?? 0)
        guard topSlot > 0 else { return 0 }
        let head = headRim()
        let tilt = (props.filter { $0.onHead }.map { $0.artSize.width }.max() ?? 0)*0.06
        let room = max(0, head.y-ScreenSpace.area(at: head).minY-h-tilt-4)
        let gap = min(h*PetPropRules.stackGap, room/CGFloat(topSlot))
        return CGFloat(slot)*gap
    }

    private func positionOnHead(_ prop: PetProp) {
        let centre = headRim()
        let h = prop.artSize.height
        prop.x = centre.x
        prop.y = centre.y - h / 2 - stackOffset(slot: prop.headSlot, height: h)
        prop.vx = 0; prop.vy = 0
    }

    func knockPotOff() {
        let stacked = props.filter { $0.onHead && $0.kind == .iron && $0.headFadeT == 0 }
        guard let top = stacked.max(by: { $0.headSlot < $1.headSlot }) else { return }
        top.headFadeT = 1e-6
        controller?.model.flinchForPot()
        onSound(.potOff)
        Log.write("iron pot knocked off")
    }

    func handleDoubleClick(at point: CGPoint) -> Bool {
        guard hasPotOnHead else { return false }
        let centre = knockCentre()
        let h = artHeight()
        let onFace = abs(point.x-centre.x) < h*PetPropRules.headBoxHalfW && abs(point.y-centre.y) < h*PetPropRules.headBoxHalfH
        let onHat = props.contains { $0.onHead && abs(point.x-$0.x) <= $0.artSize.width*0.55 && abs(point.y-$0.y) <= $0.artSize.height*0.75 }
        guard onFace || onHat else { lastKnockTime = -100; return false }
        let now = ProcessInfo.processInfo.systemUptime
        let near = abs(point.x - lastKnockPoint.x) <= PetPropRules.knockSlop
            && abs(point.y - lastKnockPoint.y) <= PetPropRules.knockSlop
        if near, now - lastKnockTime <= PetPropRules.knockInterval {
            knockPotOff()
            lastKnockTime = -100
            return true
        }
        lastKnockTime = now
        lastKnockPoint = point
        return false
    }

    // MARK: Radar values

    private func plate(for prop: PetProp) -> RadarPlate {
        var plate = RadarPlate()
        let girl = petRef()
        let dx = prop.x - girl.x
        let dy = prop.y - girl.y
        let dist = max(0.000001, hypot(dx, dy))
        let ux = dx / dist, uy = dy / dist
        let closure = -(prop.vx * ux + prop.vy * uy)
        let alt = -dy
        let side = controller?.side ?? 150
        plate.s = PetPropRules.radarFraction * artSizes(side: side).rice.width
        plate.distText = String(format: "%.1f kpt", max(0, dist) / 1000)
        plate.closureText = Self.numberText(closure) + " pt/s"
        plate.altText = Self.numberText(alt) + " pt"
        plate.dirDeg = atan2(uy, ux) * 180 / .pi
        return plate
    }

    private static func numberText(_ value: CGFloat) -> String {
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        if rounded == 0 { return "0" }
        return String(format: "%.0f", rounded)
    }

    // MARK: Layout, radar overlay, mouse routing

    func confine(_ prop: PetProp) {
        let a = ScreenSpace.area(at: CGPoint(x: prop.x, y: prop.y))
        prop.x = min(a.maxX - prop.artSize.width/2, max(a.minX + prop.artSize.width/2, prop.x))
        prop.y = min(a.maxY - prop.radius, max(a.minY + prop.artSize.height-prop.radius, prop.y))
    }

    func screenDidChange() {
        ScreenSpace.refresh()
        for prop in props where !prop.onHead { confine(prop); prop.grounded = false }
        hideRadar()
        layout()
    }

    func resizeProps() {
        let sizes = artSizes(side: controller?.side ?? 150)
        for prop in props {
            prop.artSize = prop.kind == .rice ? sizes.rice : sizes.iron
            prop.radius = prop.kind == .rice ? sizes.rice.width * PetPropRules.footprintFraction : sizes.iron.height/2
            let halfW = prop.artSize.width/2 + 8
            let halfH = max(prop.radius, prop.artSize.height-prop.radius) + 8
            prop.window?.setContentSize(CGSize(width: 2*halfW, height: 2*halfH))
            if prop.onHead { positionOnHead(prop) } else { confine(prop); prop.grounded = false }
        }
        layout()
    }

    private func layout() {
        for prop in props where !prop.onHead {
            guard let window = prop.window else { continue }
            let origin = appKitOrigin(centre: CGPoint(x: prop.x, y: prop.y), size: window.frame.size)
            if window.frame.origin != origin { window.setFrameOrigin(origin) }
            let alpha = prop.fed ? max(0, 1-prop.dieT/PetPropRules.feedFade) : 1
            if window.alphaValue != alpha { window.alphaValue = alpha }
            if !prop.grounded || prop.squish != 0 || prop.fed { prop.view?.needsDisplay = true }
        }
    }

    /// Hats share the character's CGContext, so activating its window cannot reorder them.
    func drawHead(_ ctx: CGContext, in view: PetView) {
        guard let image = PetAssets.ironArt else { return }
        for prop in props.filter({ $0.onHead }).sorted(by: { $0.headSlot < $1.headSlot }) {
            let c = localHeadCentre(prop, in: view)
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: (view.mirrored ? 1 : -1)*PetPropRules.ironTiltDeg * .pi / 180)
            ctx.setAlpha(prop.headFadeT > 0 ? max(0, 1-prop.headFadeT/PetPropRules.potFade) : 1)
            ctx.draw(image, in: CGRect(x: -prop.artSize.width/2, y: -prop.artSize.height/2,
                                      width: prop.artSize.width, height: prop.artSize.height))
            ctx.restoreGState()
        }
    }

    func hatContains(_ point: CGPoint, in view: PetView) -> Bool {
        for p in props where p.onHead {
            let c = localHeadCentre(p, in: view)
            let theta = (view.mirrored ? 1 : -1)*PetPropRules.ironTiltDeg * .pi / 180
            let dx = point.x-c.x, dy = point.y-c.y
            let x = dx*cos(theta)+dy*sin(theta), y = -dx*sin(theta)+dy*cos(theta)
            if abs(x) <= p.artSize.width/2 && abs(y) <= p.artSize.height/2 { return true }
        }
        return false
    }

    private func localHeadCentre(_ prop: PetProp, in view: PetView) -> CGPoint {
        let rect = PetLayout.spriteRect(in: view.bounds)
        let fx = view.mirrored ? 1-PetPropRules.headXFraction : PetPropRules.headXFraction
        let rim = CGPoint(x: rect.minX+rect.width*fx,
                          y: rect.maxY-rect.height*PetPropRules.headRimFraction)
        return CGPoint(x: rim.x, y: rim.y+prop.artSize.height/2+stackOffset(slot: prop.headSlot, height: prop.artSize.height))
    }

    /// Remove the hidden crown along the PNG's curved lower rim. Work inside
    /// PetView's sprite transparency layer: side hair outside the pot survives,
    /// and the original crown gradually returns while the pot fades away.
    func maskCrown(_ ctx: CGContext, in view: PetView) {
        guard let pot = props.first(where: { $0.onHead && $0.headSlot == 0 }),
              let first = PetAssets.ironLowerRim.first,
              let last = PetAssets.ironLowerRim.last else { return }
        let opacity = pot.headFadeT > 0 ? max(0, 1-pot.headFadeT/PetPropRules.potFade) : 1
        guard opacity > 0 else { return }
        let c = localHeadCentre(pot, in: view)
        let theta = (view.mirrored ? 1 : -1)*PetPropRules.ironTiltDeg * .pi / 180
        let w = pot.artSize.width, h = pot.artSize.height
        // One logical pixel of overlap keeps antialiased rim pixels backed by hair.
        let overlap: CGFloat = min(1, w/150)
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x*w, y: p.y*h+overlap) }
        let seam = CGMutablePath()
        seam.move(to: point(first))
        for p in PetAssets.ironLowerRim.dropFirst() { seam.addLine(to: point(p)) }
        let cut = seam.mutableCopy()!
        let top = view.bounds.height+abs(c.y)+w
        cut.addLine(to: CGPoint(x: last.x*w, y: top))
        cut.addLine(to: CGPoint(x: first.x*w, y: top))
        cut.closeSubpath()

        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: theta)
        ctx.setBlendMode(.destinationOut)
        ctx.setFillColor(NSColor.black.withAlphaComponent(opacity).cgColor)
        ctx.addPath(cut); ctx.fillPath()
        // Contact shadow only touches existing hair under the curved lip.
        ctx.setBlendMode(.sourceAtop)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.16*opacity).cgColor)
        ctx.setLineWidth(max(0.7, w*0.005))
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        ctx.addPath(seam); ctx.strokePath()
        ctx.restoreGState()
    }

    private func updateMouseRouting(_ cursor: CGPoint) {
        guard !isMenuTracking else { return }
        let hovered = bowl(at: cursor)
        for prop in props {
            guard let window = prop.window else { continue }
            let active = prop.dragging || (prop === hovered)
            if window.ignoresMouseEvents == active { window.ignoresMouseEvents = !active }
        }
    }

    var requiredHeadHeight: CGFloat {
        guard let v = controller?.view else { return 0 }
        return props.filter { $0.onHead }.map {
            localHeadCentre($0, in: v).y + $0.artSize.height/2 + $0.artSize.width*0.06 + 6
        }.max() ?? 0
    }

    private func updateRadarOverlay() {
        let live = props.filter { $0.kind == .rice && !$0.fed && $0.plate.on }
        let ids = Set(live.map { ObjectIdentifier($0) })
        for id in Array(radars.keys) where !ids.contains(id) {
            radars[id]?.window.orderOut(nil)
            radars[id]?.window.close()
            radars[id]?.window.contentView = nil
            radars.removeValue(forKey: id)
        }
        for p in live {
            let id = ObjectIdentifier(p)
            let z = p.plate.s
            let area = ScreenSpace.area(at: CGPoint(x: p.x, y: p.y))
            let wanted = CGRect(x: p.x-z*3, y: p.y-z*2.6, width: z*6, height: z*4.4)
            let box = wanted.intersection(area)
            guard !box.isNull, box.width > z*1.5, box.height > z*1.5 else { continue }
            let frame = CGRect(origin: ScreenSpace.up(CGPoint(x: box.minX, y: box.maxY)), size: box.size)
            if radars[id] == nil { radars[id] = makeRadar(frame) }
            guard let overlay = radars[id] else { continue }
            if overlay.window.frame != frame { overlay.window.setFrame(frame, display: false) }
            overlay.view.plates = [(CGPoint(x: p.x-box.minX, y: p.y-box.minY), p.plate)]
            overlay.view.needsDisplay = true
        }
    }

    private func makeRadar(_ frame: CGRect) -> (window: RadarWindow, view: RadarOverlayView) {
        let w = RadarWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue+1)
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.ignoresMouseEvents = true
        let v = RadarOverlayView(frame: CGRect(origin: .zero, size: frame.size))
        v.autoresizingMask = [.width, .height]
        w.contentView = v
        if visible { w.orderFrontRegardless() }
        return (w, v)
    }

    private func hideRadar() {
        for pair in radars.values { pair.window.orderOut(nil); pair.window.close(); pair.window.contentView = nil }
        radars.removeAll()
    }
}
