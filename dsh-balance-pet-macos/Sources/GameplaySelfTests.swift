import AppKit

/// Regressions use the actual accounting and prop objects, with offscreen windows.
enum GameplaySelfTests {
    static func run(_ expect: (Bool, String) -> Void) {
        ScreenSpace.refresh()
        let meterURL = PetPaths.support.appendingPathComponent("usage-fixture.json")
        defer { try? FileManager.default.removeItem(at: meterURL) }
        try? FileManager.default.removeItem(at: meterURL)
        let meter = UsageMeter(url: meterURL)
        let now = Date()
        meter.observe(cents: 1000, at: now); meter.observe(cents: 990, at: now.addingTimeInterval(30))
        expect(meter.todayCents == 10 && abs(meter.hourlyRate-12)<0.001, "observed usage and rate use real balance changes and elapsed time")
        meter.observe(cents: 1290, at: now.addingTimeInterval(60))
        expect(meter.todayCents == 10, "top-ups do not reduce or inflate observed usage")
        let restored = UsageMeter(url: meterURL)
        expect(restored.todayCents == 10, "observed daily usage survives restarting the app")
        if let hit = PetAssets.resourceURL(named: "hit.mp3"), let data = try? Data(contentsOf: hit) {
            let custom = SoundBank.customURL(for: .hit)
            let previous = try? Data(contentsOf: custom)
            try? FileManager.default.createDirectory(at: custom.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: custom)
            expect(NSSound(contentsOf: custom, byReference: true) != nil, "imported sound files decode under their persisted filename")
            if let previous = previous { try? previous.write(to: custom) }
            else { try? FileManager.default.removeItem(at: custom) }
        }
        expect(PetAssets.patHands.count == 5 && PetAssets.patHands.allSatisfy { $0.width == 446 && $0.height == 392 },
               "all five authentic Windows head-pat frames load")
        for cue in PetSound.allCases {
            expect(SoundBank.url(for: cue).flatMap { NSSound(contentsOf: $0, byReference: true) } != nil,
                   "\(cue.file): bundled cue decodes")
        }
        let read: (Double) -> BalanceReading = { BalanceReading(normalCny: $0, bonusCny: 0, spentCny: nil, raw: "") }
        let m = PetModel(); m.suppressCreditFlourish = true
        m.apply(reading: read(10), snap: true)
        m.apply(reading: read(13), snap: false)
        expect(m.heldCreditCents == 300 && m.displayedCents == 1000 && m.realCents == 1300,
               "a real recharge remains in its bowl until feeding")
        m.blockDeductions = true
        m.apply(reading: read(12.99), snap: false)
        for _ in 0..<90 { m.tick(1.0/30) }
        expect(m.displayedCents == 1000 && !m.cueRunning, "waiting credit pauses deductions without freezing the bowl deadline")
        m.deliverCredit(cents: 300, test: false); m.blockDeductions = false
        for _ in 0..<90 { m.tick(1.0/30) }
        expect(m.displayedCents == 1299 && m.heldCreditCents == 0, "feeding followed by concurrent spending books each cent once")
        m.deliverCredit(cents: 300, test: true)
        expect(m.displayedCents == 1299 && m.realCents == 1299, "test feeding cannot inflate the server or printed balance")
        m.apply(reading: read(15.99), snap: false); m.apply(reading: read(17.99), snap: false)
        m.deliverCredit(cents: 200, test: false)
        expect(m.heldCreditCents == 300 && m.displayedCents == 1499, "several top-ups can be delivered out of order")
        m.forceSnapToReal()
        expect(m.heldCreditCents == 0 && m.displayedCents == 1799, "manual refresh settles all held credits")
        m.apply(reading: read(-9e16), snap: true); m.apply(reading: read(9e16), snap: false)
        expect(m.heldCreditCents == 0 && m.realCents == m.displayedCents, "overflowing credit differences snap safely")

        ScreenSpace.configure(frames: [CGRect(x: -1280, y: 0, width: 1280, height: 1024), CGRect(x: 0, y: 0, width: 1920, height: 1080)],
            visible: [CGRect(x: -1280, y: 80, width: 1280, height: 920), CGRect(x: 0, y: 90, width: 1920, height: 966)])
        let point = CGPoint(x: -900, y: 300)
        expect(ScreenSpace.up(ScreenSpace.down(point)) == point, "negative-origin monitors preserve screen coordinates")
        let multi = PropSystem(visible: false)
        multi.petRef = { CGPoint(x: 300, y: 500) }
        multi.spawnRice(amount: 3, test: true)
        if let r = multi.props.first {
            expect(abs(multi.appKitOrigin(centre: CGPoint(x: r.x, y: r.y), size: r.window.frame.size).x+r.window.frame.width/2-(r.x+ScreenSpace.union.minX))<0.1, "prop windows include the virtual desktop's negative X origin")
            r.y = 2000; multi.confine(r)
            expect(r.y+r.radius <= ScreenSpace.workAreas[0].maxY, "each monitor uses its own Dock-safe floor")
        }
        multi.removeAll(); ScreenSpace.refresh()

        let delegate = BalanceSessionDelegate()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://example.invalid")!)
        var rejected = false
        delegate.register(task) { result in if case .failure = result { rejected = true } }
        delegate.urlSession(session, dataTask: task, didReceive: Data(repeating: 0, count: BalanceSessionDelegate.maxResponseBytes))
        delegate.urlSession(session, dataTask: task, didReceive: Data([0]))
        delegate.urlSession(session, task: task, didCompleteWithError: nil)
        expect(rejected, "streamed response bytes are capped before an unbounded body can accumulate")
        session.invalidateAndCancel()

        let system = PropSystem(visible: false)
        let area = ScreenSpace.workAreas[0]
        let head = CGPoint(x: area.midX, y: area.midY)
        system.headRim = { head }; system.knockCentre = { head }; system.petRef = { head }
        system.spawnRice(amount: 3, test: true)
        let rice = system.props[0]
        system.beginDrag(rice, at: CGPoint(x: rice.x, y: rice.y))
        system.drag(rice, to: CGPoint(x: head.x, y: area.maxY+500))
        system.endDrag(rice)
        expect(rice.y+rice.radius <= area.maxY+0.01, "rice released over the Dock remains above visibleFrame.minY")
        rice.x = area.midX; rice.y = area.maxY+100; system.confine(rice)
        expect(rice.y+rice.radius <= area.maxY+0.01, "screen changes recover a bowl from behind the Dock")
        system.removeAll()
        system.spawnIronAboveHead()
        let pot = system.props[0]
        for _ in 0..<40 { system.tick(1.0/30, cursor: .zero) }
        expect(pot.onHead && pot.window?.isVisible == false, "a seated pot stops using its own window")
        system.spawnIronAboveHead()
        let second = system.props.last!
        second.x = pot.x; second.y = pot.y-pot.artSize.height*0.7; second.vy = 50
        for _ in 0..<10 { system.tick(1.0/30, cursor: .zero) }
        expect(second.onHead && second.headSlot == 1, "a second pot seats on the existing stack instead of slot zero")
        _ = system.handleDoubleClick(at: head); _ = system.handleDoubleClick(at: head)
        expect(second.headFadeT > 0 && pot.headFadeT == 0, "double-click removes only the uppermost pot")
        for _ in 0..<30 { system.tick(1.0/30, cursor: .zero) }
        expect(system.props.count == 1 && system.props[0] === pot, "the knocked pot is removed after its fade")
        system.removeAll()

        var released = 0
        system.onFeed = { _, _ in released += 1 }
        system.spawnRice(amount: 3, test: true)
        let feed = system.props[0]
        system.petBounds = { CGRect(x: head.x-80, y: head.y-80, width: 160, height: 160) }
        system.petSolid = { _ in true }
        system.beginDrag(feed, at: CGPoint(x: feed.x, y: feed.y))
        system.drag(feed, to: head)
        expect(feed.fed && released == 1, "dragging rice onto the opaque character feeds before mouse-up")
        for _ in 0..<30 { system.tick(1.0/30, cursor: .zero) }
        expect(released == 1 && system.props.allSatisfy { $0.kind == .iron }, "a bowl feeds once and leaves a pot")
        system.removeAll(); system.petSolid = { _ in false }; system.petBounds = { .zero }
        system.spawnRice(amount: 3, test: true)
        let waiting = system.props[0]
        system.tick(0, cursor: .zero)
        expect(waiting.plate.on && !waiting.plate.locked, "radar shows immediately when rice appears")
        for _ in 0..<300 where !waiting.hasLanded { system.tick(1.0/30, cursor: .zero) }
        expect(waiting.hasLanded && waiting.waitTime == 0, "wait clock begins after the first floor contact")
        for _ in 0..<299 { system.tick(1.0/30, cursor: .zero) }
        expect(!waiting.plate.locked && !waiting.beingSucked, "rice stays unlocked before ten seconds after landing")
        for _ in 0..<2 { system.tick(1.0/30, cursor: .zero) }
        expect(waiting.plate.locked && !waiting.beingSucked, "ten seconds locks the target without immediate attraction")
        for _ in 0..<31 { system.tick(1.0/30, cursor: .zero) }
        expect(waiting.beingSucked, "one second after lock triggers batch attraction")
        system.removeAll()

        autoreleasepool {
            let c = PetController(visible: false)
            c.model.apply(reading: read(10), snap: true)
            let v = PetView(model: c.model); c.view = v; v.controller = c; c.props.controller = c
            let w = PetWindow(contentRect: v.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false; w.contentView = v
            c.props.headRim = { let r = v.spriteRectScreenDown; return CGPoint(x: r.minX+r.width*PetPropRules.headXFraction, y: r.minY+r.height*PetPropRules.headRimFraction) }
            c.props.knockCentre = c.props.headRim
            c.props.spawnIronAboveHead()
            if let p = c.props.props.first {
                c.props.attachPot(p, slot: 0)
                let local = w.convertPoint(fromScreen: ScreenSpace.up(c.props.headRim()))
                if let down = NSEvent.mouseEvent(with: .leftMouseDown, location: local, modifierFlags: [], timestamp: 0,
                                                windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
                   let up = NSEvent.mouseEvent(with: .leftMouseUp, location: local, modifierFlags: [], timestamp: 0,
                                              windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
                    v.mouseDown(with: down); v.mouseUp(with: up)
                    expect(p.onHead && p.headFadeT == 0 && p.window?.isVisible == false,
                           "the real character click handler leaves a worn pot in the character drawing layer")
                    v.mouseDown(with: down); v.mouseUp(with: up)
                    expect(p.headFadeT > 0, "the real character double-click path removes a worn pot")
                }
            }
            c.props.removeAll(); w.contentView = nil; w.close()
        }

        weak var freedProp: PetProp?
        weak var freedView: PropView?
        for _ in 0..<100 {
            autoreleasepool {
                system.spawnRice(amount: 3, test: true)
                freedProp = system.props.first; freedView = system.props.first?.view
                system.removeAll()
            }
        }
        expect(freedProp == nil && freedView == nil, "100 create/remove cycles release prop and view objects")
        for _ in 0..<150 { system.spawnRice(amount: 3, test: true) }
        expect(system.props.count <= PropSystem.maxProps, "repeated recharge demos have a hard bound on native windows")
        system.tick(.nan, cursor: .zero); system.tick(.infinity, cursor: .zero)
        expect(system.props.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "nonfinite clock values cannot poison physics")
        system.removeAll()

        var pat = PatGesture()
        for i in 0..<70 {
            pat.tick(1.0/60, point: CGPoint(x: 100+(i%2)*20,y: 100), onPet: true,
                     button: false, movingPet: false, enabled: true, hasPot: false, knock: {})
        }
        expect(pat.active, "a sustained hover stroke triggers a pat")
        pat.tick(1.0/30, point: .zero, onPet: true, button: true, movingPet: false,
                 enabled: true, hasPot: false, knock: {})
        expect(!pat.active, "pressing any button cancels the pat before dragging")
        for _ in 0..<90 { pat.tick(1.0/60, point: .zero, onPet: true, button: false,
                                  movingPet: false, enabled: true, hasPot: false, knock: {}) }
        expect(!pat.active, "a stationary hovering cursor does not trigger a pat")
        for character in PetCharacter.allCases {
            guard let sprite = PetAssets.sprite(for: character), let url = PetAssets.resourceURL(named: character.resourceName),
                  let data = try? Data(contentsOf: url), let bitmap = NSBitmapImageRep(data: data) else { continue }
            var matches = true
            for y in stride(from: 11, to: 1024, by: 91) { for x in stride(from: 17, to: 1536, by: 113) {
                let expected = (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 8.0/255
                if sprite.isOpaque(normalizedX: (CGFloat(x)+0.5)/1536, yFromTop: (CGFloat(y)+0.5)/1024) != expected { matches = false }
            } }
            expect(matches, "\(character.displayName): fast feeding mask matches source alpha orientation")
        }
        ScreenSpace.refresh()
    }
}
