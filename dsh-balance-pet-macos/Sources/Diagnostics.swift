import AppKit
import CoreGraphics

/// Head-less verification entry points. These exist so the app can be checked
/// without screen-recording permission: `--selftest` exercises the accounting,
/// `--check` performs one real request, `--snapshot` renders the widget
/// off-screen to PNG, and `--windows` reports the live overlay geometry.
enum Diagnostics {

    static func wantsRun() -> Bool {
        let a = CommandLine.arguments
        return a.contains("--selftest") || a.contains("--check")
            || a.contains("--snapshot") || a.contains("--windows")
            || a.contains("--screens") || a.contains("--reset") || a.contains("--gameplay-snapshot")
            || a.contains("--props-preview") || a.contains("--expression-preview")
    }

    static func run() -> Int32 {
        let a = CommandLine.arguments
        if a.contains("--selftest") { return selfTest() }
        if let i = a.firstIndex(of: "--gameplay-snapshot") { return gameplaySnapshot(into: i+1<a.count ? a[i+1] : "./gameplay-snapshots") }
        if a.contains("--screens") { return screens() }
        if a.contains("--windows") { return windowProbe() }
        if a.contains("--reset") { return reset() }
        if let i = a.firstIndex(of: "--snapshot") {
            return snapshot(into: i + 1 < a.count ? a[i + 1] : "./snapshots")
        }
        if let i = a.firstIndex(of: "--props-preview") {
            return propsPreview(into: i + 1 < a.count ? a[i + 1] : "./props-preview")
        }
        if let i = a.firstIndex(of: "--expression-preview") {
            return expressionPreview(into: i + 1 < a.count ? a[i + 1] : "./expression-preview")
        }
        return check()
    }

    /// Reset just the position, preserving sound, size, and polling preferences.
    static func reset() -> Int32 {
        do {
            let lock = try InstanceLock(directory: PetPaths.support)
            withExtendedLifetime(lock) {
                var state = PetState.load()
                state.windowOrigin = nil
                state.save()
            }
            print("saved window position cleared; other settings preserved")
            return 0
        } catch {
            print("cannot reset while this profile is running or unwritable; quit the pet first")
            return 1
        }
    }

    /// Print the real NSScreen layout, which does not always match what
    /// system_profiler reports (scaled HiDPI modes, virtual displays).
    static func screens() -> Int32 {
        _ = NSApplication.shared
        print("screens: \(NSScreen.screens.count)")
        for (i, s) in NSScreen.screens.enumerated() {
            let f = s.frame, v = s.visibleFrame
            print(String(format: "  [%d] %@", i, s.localizedName))
            print(String(format: "      frame        (%.0f,%.0f %.0fx%.0f)", f.origin.x, f.origin.y, f.width, f.height))
            print(String(format: "      visibleFrame (%.0f,%.0f %.0fx%.0f)", v.origin.x, v.origin.y, v.width, v.height))
            print(String(format: "      backingScale %.1f", s.backingScaleFactor))
        }
        if let m = NSScreen.main {
            print(String(format: "main: %@ visibleFrame (%.0f,%.0f %.0fx%.0f)",
                         m.localizedName, m.visibleFrame.origin.x, m.visibleFrame.origin.y,
                         m.visibleFrame.width, m.visibleFrame.height))
        } else {
            print("main: nil")
        }
        return 0
    }

    // MARK: - Accounting self-test

    private static var failures = 0

    private static func expect(_ condition: Bool, _ label: String) {
        print((condition ? "  PASS  " : "  FAIL  ") + label)
        if !condition { failures += 1 }
    }

    private static func reading(_ cny: Double) -> BalanceReading {
        BalanceReading(normalCny: cny, bonusCny: 0, spentCny: nil, raw: "")
    }

    static func selfTest() -> Int32 {
        _ = NSApplication.shared
        failures = 0
        print("== balance and animation regressions ==")
        ModelSelfTests.run(expect)
        GameplaySelfTests.run(expect)
        SnapSelfTests.run(expect)
        CrownSelfTests.run(expect)
        print("\n== request scheduling regressions ==")
        PollScheduleSelfTests.run(expect)
        print("\n== network and credential fixtures (offline) ==")
        failures += NetworkSelfTests.run()

        print("\n== bundled artwork, audio, and hit testing ==")
        ArtworkSelfTests.run(expect)

        print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
        return failures == 0 ? 0 : 1
    }

    static func gameplaySnapshot(into directory: String) -> Int32 {
        _ = NSApplication.shared
        let dest = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for character in PetCharacter.allCases { for mirror in [false, true] {
            var state = PetState(); state.sizeIndex = 3; state.soundOn = false; state.mirrored = mirror
            let c = PetController(state: state, visible: false)
            c.model.apply(reading: BalanceReading(normalCny: 100, bonusCny: 0, spentCny: nil, raw: ""), snap: true)
            let v = PetView(model: c.model, character: character)
            v.frame = CGRect(origin: .zero, size: PetLayout.windowSize(side: 280))
            v.mirrored = mirror; v.controller = c; c.view = v; c.props.controller = c
            c.props.headRim = { CGPoint(x: 500, y: 500) }
            for count in 1...3 {
                c.props.spawnIronAboveHead()
                if let p = c.props.props.last { c.props.attachPot(p, slot: count-1) }
                v.setExpression(.calm)
                v.frame.size.height = max(v.frame.height, c.props.requiredHeadHeight)
                let file = dest.appendingPathComponent("hat-\(character.rawValue)-\(mirror ? "right" : "left")-\(count).png")
                if !render(v, to: file, transparent: false) { return 1 }
            }
            c.props.removeAll()
            var gesture = PatGesture()
            for i in 0..<100 {
                gesture.tick(1.0/60, point: CGPoint(x: (i%2)*20, y: 100), onPet: true, button: false,
                             movingPet: false, enabled: true, hasPot: false, knock: {})
                if gesture.active { break }
            }
            for frame in 0..<5 {
                v.pat = gesture; v.setExpression(.nervous)
                let file = dest.appendingPathComponent("pat-\(character.rawValue)-\(mirror ? "right" : "left")-\(frame).png")
                if !render(v, to: file, transparent: false) { return 1 }
                gesture.tick(0.04, point: CGPoint(x: 200+frame*20, y: 100), onPet: true, button: false,
                             movingPet: false, enabled: true, hasPot: false, knock: {})
            }
        } }
        return 0
    }

    // MARK: - Live request

    static func check() -> Int32 {
        print("== credential ==")
        guard let cred = CredentialStore.resolve() else {
            print("no credential found")
            return 1
        }
        print("mode:     \(cred.mode)")
        print("endpoint: \(cred.endpoint.absoluteString)")
        print("source:   \(cred.source)")
        print("token:    \(cred.token.count) chars")

        print("\n== live request ==")
        do {
            let r = try BalanceClient.fetch(cred)
            print(String(format: "normal CNY: %.4f", r.normalCny))
            print(String(format: "bonus  CNY: %.4f", r.bonusCny))
            print(String(format: "TOTAL  CNY: %.6f  -> displays as %.2f",
                         r.totalCny, Double(r.totalCents ?? 0) / 100))
            if let s = r.spentCny { print(String(format: "spent  CNY: %.2f", s)) }
            return 0
        } catch let e as FetchError {
            print("FAILED: \(e.describe)")
            return 2
        } catch {
            print("FAILED: \(error)")
            return 2
        }
    }

    // MARK: - Expression preview

    /// Renders all four faces so the ported expression states can be inspected
    /// without screen recording.
    static func expressionPreview(into directory: String) -> Int32 {
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = PetModel()
        model.apply(reading: BalanceReading(normalCny: 38.61, bonusCny: 0, spentCny: nil, raw: ""), snap: true)
        var written = 0
        for character in PetCharacter.allCases { for expression in PetExpression.allCases {
            let view = PetView(model: model, character: character)
            view.frame = NSRect(origin: .zero, size: PetLayout.windowSize(side: 280))
            view.setExpression(expression)
            if render(view, to: dir.appendingPathComponent("\(character.rawValue)-expression-\(expression.rawValue).png")) { written += 1 }
        } }
        print("wrote \(written) expression render(s) to \(dir.path)")
        return written == PetCharacter.allCases.count * PetExpression.allCases.count ? 0 : 1
    }

    // MARK: - Prop / radar preview

    /// Renders the radar plate and both props off-screen so their geometry can be
    /// inspected without a screen recording.
    static func propsPreview(into directory: String) -> Int32 {
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let size = NSSize(width: 900, height: 700)
        let overlay = RadarOverlayView(frame: NSRect(origin: .zero, size: size))
        var plate = RadarPlate()
        plate.on = true
        plate.s = 223
        plate.distText = "1.4 kpt"
        plate.closureText = "-152 pt/s"
        plate.altText = "312 pt"
        plate.dirDeg = -38
        overlay.plates = [(CGPoint(x: 430, y: 330), plate)]
        let canvas = NSView(frame: NSRect(origin: .zero, size: size))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.13, blue: 0.18, alpha: 1).cgColor
        overlay.frame = canvas.bounds
        canvas.addSubview(overlay)
        _ = render(canvas, to: dir.appendingPathComponent("radar.png"))

        for (index, centre) in [CGPoint(x:300,y:260),CGPoint(x:45,y:260),CGPoint(x:555,y:260)].enumerated() {
            let edge = RadarOverlayView(frame: CGRect(x:0,y:0,width:600,height:300))
            var value = RadarPlate(); value.on = true; value.locked = true; value.s = 100
            value.distText = "1.4 kpt"; value.closureText = "-152 pt/s"; value.altText = "312 pt"; value.dirDeg = -38
            edge.plates = [(centre,value)]
            _ = render(edge, to: dir.appendingPathComponent("radar-floor-\(index).png"), transparent: false)
        }

        for (name, kind) in [("rice", PetProp.Kind.rice), ("iron", PetProp.Kind.iron)] {
            let artSize = kind == .rice ? CGSize(width: 66, height: 66) : CGSize(width: 111, height: 39)
            let radius = artSize.width * 0.42
            let prop = PetProp(kind: kind, x: 100, y: 100, radius: radius, artSize: artSize)
            let halfW = artSize.width / 2 + 8
            let halfH = max(radius, artSize.height - radius) + 8
            let view = PropView(frame: NSRect(x: 0, y: 0, width: halfW * 2, height: halfH * 2))
            view.prop = prop
            let host = NSView(frame: NSRect(x: 0, y: 0, width: halfW * 2, height: halfH * 2))
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.13, blue: 0.18, alpha: 1).cgColor
            host.addSubview(view)
            _ = render(host, to: dir.appendingPathComponent("\(name).png"))
        }
        print("wrote props preview to \(dir.path)")
        return 0
    }

    // MARK: - Off-screen render

    private static func render(_ view: NSView, to url: URL, transparent: Bool = false) -> Bool {
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)

        if transparent {
            guard let png = rep.representation(using: .png, properties: [:]) else { return false }
            return (try? png.write(to: url)) != nil
        }

        guard let source = rep.cgImage,
              let canvas = CGContext(data: nil, width: rep.pixelsWide, height: rep.pixelsHigh,
                                     bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        let pixels = CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
        canvas.setFillColor(NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1).cgColor)
        canvas.fill(pixels)
        canvas.draw(source, in: pixels)
        guard let image = canvas.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    static func snapshot(into directory: String) -> Int32 {
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: directory)
        var written: [String] = []
        for character in PetCharacter.allCases {
            // Keep the original 21 filenames stable for README links.
            let prefix = character == .deepseek ? "" : character.rawValue + "/"
            let destination = prefix.isEmpty ? dir : dir.appendingPathComponent(character.rawValue)
            let names = characterSnapshots(into: destination, character: character)
            written.append(contentsOf: names.map { prefix + $0 })
        }
        print("wrote \(written.count) snapshot(s) to \(dir.path)")
        for name in written { print("  " + name) }
        return written.count == 21 * PetCharacter.allCases.count ? 0 : 1
    }

    private static func characterSnapshots(into dir: URL, character: PetCharacter) -> [String] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let side: CGFloat = 240
        let frame = NSRect(origin: .zero, size: PetLayout.windowSize(side: side))

        func makeView(_ model: PetModel) -> PetView {
            let v = PetView(model: model, character: character)
            v.frame = frame
            return v
        }

        var written: [String] = []

        // 1. Connected, idle
        let idle = PetModel()
        idle.apply(reading: BalanceReading(normalCny: 38.61, bonusCny: 0, spentCny: 31.38, raw: ""), snap: true)
        let v1 = makeView(idle)
        if render(v1, to: dir.appendingPathComponent("01-connected.png")) { written.append("01-connected.png") }

        // 2. Hurt animation: four "-0.01" labels in flight, held at peak impact
        //    so the red flash and shake offset are both visible.
        let hit = PetModel()
        hit.apply(reading: BalanceReading(normalCny: 38.65, bonusCny: 0, spentCny: 31.34, raw: ""), snap: true)
        hit.apply(reading: BalanceReading(normalCny: 38.61, bonusCny: 0, spentCny: 31.38, raw: ""), snap: false)
        var frames = 0
        while (hit.floating.count < 4 || hit.impact < 0.95) && frames < 120 {
            hit.tick(1.0 / 60.0)
            frames += 1
        }
        let v2 = makeView(hit)
        if render(v2, to: dir.appendingPathComponent("02-hit.png")) { written.append("02-hit.png") }

        // 3. Top-up celebration
        let top = PetModel()
        top.apply(reading: BalanceReading(normalCny: 20.00, bonusCny: 0, spentCny: nil, raw: ""), snap: true)
        top.apply(reading: BalanceReading(normalCny: 50.00, bonusCny: 5.50, spentCny: nil, raw: ""), snap: false)
        for _ in 0..<8 { top.tick(1.0 / 60.0) }
        let v3 = makeView(top)
        if render(v3, to: dir.appendingPathComponent("03-topup.png")) { written.append("03-topup.png") }

        // 4. No credential / offline
        let off = PetModel()
        off.setNoCredential()
        let v4 = makeView(off)
        if render(v4, to: dir.appendingPathComponent("04-offline.png")) { written.append("04-offline.png") }

        let transparent = "05-transparent.png"
        if render(v1, to: dir.appendingPathComponent(transparent), transparent: true) { written.append(transparent) }
        for preset in PetController.sizePresets {
            let sized = PetView(model: idle, character: character)
            sized.frame = NSRect(origin: .zero, size: PetLayout.windowSize(side: preset.side))
            let name = "size-\(Int(preset.side))pt.png"
            if render(sized, to: dir.appendingPathComponent(name)) { written.append(name) }
        }
        for (name, amount) in [("06-long-balance.png", 1_234_567.89), ("07-negative-balance.png", -0.05)] {
            let model = PetModel()
            model.apply(reading: reading(amount), snap: true)
            if render(makeView(model), to: dir.appendingPathComponent(name)) { written.append(name) }
            for preset in PetController.sizePresets {
                let sized = PetView(model: model, character: character)
                sized.frame = NSRect(origin: .zero, size: PetLayout.windowSize(side: preset.side))
                let sizeName = "size-\(Int(preset.side))pt-\(name)"
                if render(sized, to: dir.appendingPathComponent(sizeName)) { written.append(sizeName) }
            }
        }
        let stale = PetModel()
        stale.apply(reading: reading(38.61), snap: true)
        stale.fail(.transport("离线示例"))
        let staleName = "08-disconnected.png"
        if render(makeView(stale), to: dir.appendingPathComponent(staleName)) { written.append(staleName) }

        let detail = makeView(idle)
        detail.frame = NSRect(origin: .zero, size: PetLayout.windowSize(side: 640))
        let detailName = "09-tablet-detail.png"
        if render(detail, to: dir.appendingPathComponent(detailName)) { written.append(detailName) }

        return written
    }

    // MARK: - Live status
    //
    // Reading another process's window through CGWindowListCopyWindowInfo needs
    // Screen Recording permission, so the running pet publishes its own geometry
    // and connection state to status.json instead and we read that.

    static func windowProbe() -> Int32 {
        guard let data = try? Data(contentsOf: PetPaths.statusURL) else {
            print("no status file at \(PetPaths.statusURL.path)")
            print("(the pet has not run yet, or it cannot write there)")
            return 1
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("status file is not valid JSON")
            return 1
        }
        let age = Date().timeIntervalSince1970 - (obj["updatedAt"] as? Double ?? 0)
        let live = (obj["running"] as? Bool == true) && age >= -5 && age <= 5
        print(String(format: "status age: %.1fs%@", age, live ? "" : "  <-- stopped or stale"))
        let keys = ["running", "pid", "character", "characterName", "connected", "display", "real", "statusText",
                    "lastError", "credential", "spentCny",
                    "windowX", "windowY", "windowW", "windowH",
                    "windowLevel", "windowVisible", "onActiveSpace", "opaque", "screen"]
        for k in keys {
            if let v = obj[k] { print("  \(k.padding(toLength: 15, withPad: " ", startingAt: 0)) \(v)") }
        }
        return live ? 0 : 1
    }
}
