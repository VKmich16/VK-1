import AppKit
import UniformTypeIdentifiers

final class ActionBox: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire(_ sender: Any?) { handler() }
}

final class PetController: NSObject, NSApplicationDelegate, NSMenuDelegate {

    let model = PetModel()
    let usage = UsageMeter()
    private var tariffMode = false
    var view: PetView!
    private var window: PetWindow!
    private var statusItem: NSStatusItem?
    private var state: PetState
    init(state: PetState = PetState.load(), visible: Bool = true, window: PetWindow? = nil) { self.state = state; self.props = PropSystem(visible: visible); self.window = window; super.init() }
    private var credential: Credential?

    /// Recharge bowls, iron pots and the radar overlay (Windows v3 features).
    let props: PropSystem
    private let sounds = SoundBank()

    private var snapMotion: SnapMotion?
    private var idleForSnap = 0.0
    private var tickTimer: Timer?
    private var lastFrame: CFTimeInterval = CACurrentMediaTime()
    private var schedule = PollSchedule(interval: 30)
    private var statusAccum: Double = 0
    private var wakeObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    private var statusBoxes: [ActionBox] = []
    private var popupBoxes: [ActionBox] = []
    private var isMenuTracking = false


    static let sizePresets: [(title: String, side: CGFloat)] = [
        ("小", 110), ("中", 150), ("大", 210), ("特大", 280),
    ]

    var side: CGFloat {
        let i = min(max(state.sizeIndex, 0), Self.sizePresets.count - 1)
        return Self.sizePresets[i].side
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        ScreenSpace.refresh()
        credential = CredentialStore.resolve()
        schedule = PollSchedule(interval: state.pollSeconds)

        if PetAssets.sprite(for: state.character) == nil {
            state.character = .deepseek
        }
        view = PetView(model: model, character: state.character)
        view.controller = self
        view.mirrored = state.mirrored

        let content = NSRect(origin: .zero, size: PetLayout.windowSize(side: side))
        window = PetWindow(contentRect: content,
                           styleMask: [.borderless],
                           backing: .buffered,
                           defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.contentView = view
        window.alphaValue = 1.0

        model.setCredentialSource(credentialSourceLabel())
        model.onHit = { [weak self] in self?.playHit() }
        model.suppressCreditFlourish = state.bowlOnCredit
        model.hurtEffects = state.hurtEffects
        setUpProps()

        placeWindow()
        window.orderFrontRegardless()

        buildStatusItem()
        startTick()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.lastFrame = CACurrentMediaTime()
            self.schedule.wake(at: self.lastFrame)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.keepWindowVisible() }

        let f = window.frame
        Log.write(String(format: "started: size=%.0fpt frame=(%.0f,%.0f %.0fx%.0f) screen=%@ credential=%@",
                         side, f.origin.x, f.origin.y, f.width, f.height,
                         window.screen?.localizedName ?? "?",
                         credential?.shortDescription ?? "none"))
        if credential == nil {
            Log.write("no credential found; right-click the pet → 设置 API Key…")
        }

        writeStatus()
        poll(snap: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTimer?.invalidate()
        props.removeAll()
        if let observer = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let observer = screenObserver { NotificationCenter.default.removeObserver(observer) }
        state.windowOrigin = window?.frame.origin
        state.save()
        if window != nil { writeStatus(running: false) }
    }

    // MARK: - Window placement

    private func placeWindow() {
        if state.snapOnRelease { snapToCorner(animated: false, on: NSScreen.screens.first); return }
        let size = window.frame.size
        if let origin = state.windowOrigin, isOnScreen(origin: origin, size: size) {
            window.setFrameOrigin(origin)
            return
        }
        // First run: land on the primary display (the one with the menu bar)
        // rather than whichever screen the fresh window happened to open on.
        snapToCorner(animated: false, on: NSScreen.screens.first)
    }

    private func isOnScreen(origin: NSPoint, size: NSSize) -> Bool {
        let frame = NSRect(origin: origin, size: size)
        return NSScreen.screens.contains { $0.visibleFrame.contains(frame) }
    }

    private func keepWindowVisible() {
        guard let window = window else { return }
        props.screenDidChange()
        if state.snapOnRelease { snapToCorner(animated: false); state.save(); return }
        if !isOnScreen(origin: window.frame.origin, size: window.frame.size) {
            snapToCorner(animated: false)
            state.save()
        }
    }

    /// Snap to the bottom-left corner. `on` defaults to the screen the pet is
    /// currently sitting on, so dragging it to another display keeps it there.
    func homeOrigin(on screen: NSScreen? = nil) -> CGPoint? {
        guard let target = screen ?? window?.screen ?? NSScreen.main, let view = view else { return nil }
        let vf = target.visibleFrame, foot = view.solidBounds
        let x = state.mirrored ? vf.maxX-foot.maxX : vf.minX-foot.minX
        // NSWindow rounds frame origins to integral logical points. Store that same target.
        return CGPoint(x: x.rounded(.down), y: (vf.minY-foot.minY).rounded(.up))
    }

    func snapToCorner(animated: Bool, on screen: NSScreen? = nil) {
        guard let window = window, let origin = homeOrigin(on: screen) else { return }
        idleForSnap = 0
        if animated {
            snapMotion = SnapMotion(from: window.frame.origin, to: origin)
        } else {
            snapMotion = nil
            window.setFrameOrigin(origin)
        }
        state.windowOrigin = origin
    }

    func returnToLeftCorner() {
        state.mirrored = false
        view.mirrored = false
        view.needsDisplay = true
        props.resizeProps()
        snapToCorner(animated: true)
        state.save()
    }

    /// Runs from the same main-loop tick as the pet, including while menus close.
    func updateWindowMotion(_ dt: Double, buttonDown: Bool) {
        guard let window = window, let view = view, dt.isFinite, dt >= 0 else { return }
        if view.isDragging { snapMotion = nil; idleForSnap = 0; return }
        if var motion = snapMotion {
            window.setFrameOrigin(motion.advance(dt))
            snapMotion = motion.finished ? nil : motion
            if motion.finished { state.windowOrigin = window.frame.origin; state.save() }
            return
        }
        guard state.snapOnRelease, !buttonDown, !isMenuTracking, let home = homeOrigin() else { idleForSnap = 0; return }
        if hypot(home.x-window.frame.minX, home.y-window.frame.minY) <= 1 { idleForSnap = 0; return }
        idleForSnap += min(dt, 0.1)
        if idleForSnap >= 0.2 { snapToCorner(animated: true) }
    }

    func dragDidEnd() {
        state.windowOrigin = window.frame.origin
        if state.snapOnRelease { snapToCorner(animated: true) }
        state.save()
    }

    func updateHatSpace() {
        guard let window = window else { return }
        let base = PetLayout.windowSize(side: side)
        let h = max(base.height, props.requiredHeadHeight)
        if abs(window.frame.height-h) > 0.5 {
            window.setFrame(CGRect(origin: window.frame.origin, size: CGSize(width: base.width, height: h)), display: true)
        }
    }

    // MARK: - Tick

    /// Face priority ported from the Windows build: zero balance pouts, a charge
    /// being played squeezes the eyes shut, otherwise she smiles. The iron-pot
    /// cases arrive with the prop system.
    private func currentExpression() -> PetExpression {
        // Priority ported from the Windows build. The iron pot outranks a charge
        // only while no unclaimed bowl is on screen.
        if view.pat.active { return .nervous }
        if model.broke { return .aloof }
        if props.hasPotOnHead && !props.hasBowls { return .calm }
        if model.cueRunning { return .nervous }
        if props.waitingSeconds >= PetPropRules.bowlLockSeconds { return .aloof }
        return .happy
    }

    private func startTick() {
        // One 30 Hz main-loop timer drives motion, accounting, props, and head pats.
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.frameTick() }
        t.tolerance = 0.005
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t

    }

    private func frameTick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastFrame)
        lastFrame = now

        updateWindowMotion(dt, buttonDown: NSEvent.pressedMouseButtons != 0)
        let wasAnimating = model.needsAnimationFrame
        model.blockDeductions = props.hasBowls
        model.tick(dt)
        props.isMenuTracking = isMenuTracking
        props.tick(dt, cursor: ScreenSpace.down(NSEvent.mouseLocation))
        let cursor = ScreenSpace.down(NSEvent.mouseLocation)
        let wasPatting = view.pat.active
        view.pat.tick(dt, point: cursor, onPet: petSolid(at: cursor), button: NSEvent.pressedMouseButtons != 0 || isMenuTracking,
                      movingPet: view.isDragging || snapMotion != nil, enabled: state.patEnabled && PetAssets.patHands.count == 5,
                      hasPot: props.hasPotOnHead, knock: { [weak self] in self?.props.knockPotOff() })
        if wasPatting || view.pat.active { view.needsDisplay = true }
        view.setExpression(currentExpression())
        if wasAnimating || model.needsAnimationFrame { view.needsDisplay = true }

        // NSView.hitTest alone cannot pass an event through an entire window.
        // Polling the pointer needs no global input-monitoring permission.
        // AppKit owns event routing while tracking a menu and its submenus.
        // Do not touch the host window's mouse routing in that nested run loop.
        if !isMenuTracking {
            let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            let ignoresMouse = !view.isDragging && !view.containsInteractivePoint(point)
            if window.ignoresMouseEvents != ignoresMouse {
                window.ignoresMouseEvents = ignoresMouse
            }
        }
        if credential != nil { poll(snap: false) }

        statusAccum += dt
        if statusAccum >= 1.0 {
            statusAccum = 0
            let oldAreas = ScreenSpace.workAreas
            ScreenSpace.refresh()
            if oldAreas != ScreenSpace.workAreas { keepWindowVisible() }
            writeStatus()
        }
    }

    /// Publish a small liveness/geometry snapshot so the pet can be inspected
    /// from another process without screen-recording permission.
    private func writeStatus(running: Bool = true) {
        let f = window.frame
        let obj: [String: Any] = [
            "running": running,
            "version": "1.4.3",
            "props": props.props.count,
            "headPots": props.props.filter { $0.onHead }.count,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "character": view.character.rawValue,
            "characterName": view.character.displayName,
            "connected": model.connected,
            "display": model.displayString,
            "real": model.realString,
            "statusText": model.statusText,
            "lastError": model.lastError ?? "",
            "credential": model.credentialSource ?? "",
            "spentCny": model.spentCny ?? -1,
            "windowX": Double(f.origin.x),
            "windowY": Double(f.origin.y),
            "windowW": Double(f.width),
            "windowH": Double(f.height),
            "windowLevel": Double(window.level.rawValue),
            "windowVisible": window.isVisible,
            "onActiveSpace": window.isOnActiveSpace,
            "opaque": window.isOpaque,
            "screen": window.screen?.localizedName ?? "",
            "updatedAt": Date().timeIntervalSince1970,
        ]
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: PetPaths.statusURL, options: .atomic)
        }
    }

    // MARK: - Polling

    private func poll(snap: Bool, force: Bool = false) {
        guard let cred = credential else {
            model.setNoCredential()
            model.setCredentialSource(credentialSourceLabel())
            view.needsDisplay = true
            return
        }
        guard let request = schedule.begin(at: CACurrentMediaTime(), force: force) else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let outcome: Result<BalanceReading, Error>
            do { outcome = .success(try BalanceClient.fetch(cred)) }
            catch { outcome = .failure(error) }

            DispatchQueue.main.async {
                let failure: FetchError?
                if case .failure(let error) = outcome {
                    failure = (error as? FetchError) ?? .transport(error.localizedDescription)
                } else { failure = nil }
                guard self.schedule.finish(request, error: failure, at: CACurrentMediaTime()) else { return }
                switch outcome {
                case .success(let reading):
                    let wasDisconnected = !self.model.connected
                    if let cents = reading.totalCents { self.usage.observe(cents: cents) }
                    self.updateTariff()
                    let previousHeld = self.model.heldCreditCents
                    if snap || wasDisconnected { self.props.removeAll() }
                    if snap || wasDisconnected {
                        self.model.apply(reading: reading, snap: true)
                    } else {
                        self.model.apply(reading: reading, snap: false)
                    }
                    if !snap, !wasDisconnected, self.state.bowlOnCredit,
                       self.model.heldCreditCents > previousHeld {
                        self.props.spawnRice(cents: self.model.heldCreditCents - previousHeld)
                    }
                    Log.write(String(format: "poll ok: CNY %.4f (normal %.4f + bonus %.4f)",
                                     reading.totalCny, reading.normalCny, reading.bonusCny))
                case .failure(let error):
                    let fe = (error as? FetchError) ?? .transport(error.localizedDescription)
                    self.model.fail(fe)
                    if case .rateLimited = fe {
                        Log.write(String(format: "rate limited, next poll in %.0fs",
                                         max(0, self.schedule.nextPollAt - CACurrentMediaTime())))
                    }
                }
                self.view.needsDisplay = true
                self.writeStatus()
            }
        }
    }

    private func credentialSourceLabel() -> String? {
        credential?.shortDescription
    }

    // MARK: - Recharge props

    private func setUpProps() {
        props.controller = self
        props.petBounds = { [weak self] in self?.view?.spriteRectScreenDown ?? .zero }
        props.petRef = { [weak self] in self?.petPoint(0.7622, 0.3484) ?? .zero }
        props.headRim = { [weak self] in self?.petPoint(PetPropRules.headXFraction, PetPropRules.headRimFraction) ?? .zero }
        props.knockCentre = { [weak self] in self?.petPoint(PetPropRules.headXFraction, 0.35) ?? .zero }
        props.artHeight = { [weak self] in self?.view?.spriteRectScreenDown.height ?? 150 }
        props.petSolid = { [weak self] in self?.petSolid(at: $0) ?? false }
        props.onFeed = { [weak self] amount, test in self?.handleFeed(amount: amount, test: test) }
        props.onSound = { [weak self] in self?.sounds.play($0) }
        sounds.volumes = state.cueVolumes.map { Float($0) }
        sounds.enabled = state.soundOn
        sounds.preload()

        // Diagnostics: verify the alpha mask orientation and exercise the prop
        // system without a mouse. DSHPET_SPAWN_BOWL=1 drops a test bowl.
        Log.write("alpha probe: y85=\(petSolid(at: petPoint(0.5, 0.85))) y15=\(petSolid(at: petPoint(0.5, 0.15)))")
        if ProcessInfo.processInfo.environment["DSHPET_SPAWN_BOWL"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.props.spawnRice(amount: 3.0, test: true)
            }
        }
        if let hits = ProcessInfo.processInfo.environment["DSHPET_TEST_HIT"], let n = Int(hits), n > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.model.playDemo(times: n)
            }
        }
        if ProcessInfo.processInfo.environment["DSHPET_TEST_POT"] == "1" {
            // Drop an iron pot above her head, then knock it off with a synthetic
            // double click: exercises seating, stacking and removal without a mouse.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self else { return }
                self.props.spawnIronAboveHead()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                Log.write("pot test: onHead=\(self.props.hasPotOnHead)")
                let point = self.petPoint(PetPropRules.headXFraction, 0.35)
                _ = self.props.handleDoubleClick(at: point)
                _ = self.props.handleDoubleClick(at: point)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    Log.write("pot test after knock: onHead=\(self?.props.hasPotOnHead ?? false)")
                }
            }
        }
    }

    /// Fractions are measured on the 1536x1024 artwork, y down from its top.
    func petPoint(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
        guard let view = view else { return .zero }
        let rect = view.spriteRectScreenDown
        return CGPoint(x: rect.minX + rect.width * (state.mirrored ? 1-fx : fx), y: rect.minY + rect.height * fy)
    }

    func petSolid(at point: CGPoint) -> Bool {
        guard let view = view, let sprite = view.hitSprite else { return false }
        let rect = view.spriteRectScreenDown
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return false }
        return sprite.isOpaque(normalizedX: state.mirrored ? 1-(point.x-rect.minX)/rect.width : (point.x-rect.minX)/rect.width,
                               yFromTop: (point.y - rect.minY) / rect.height)
    }

    private func handleFeed(amount: Int, test: Bool) {
        sounds.play(.feed)
        model.deliverCredit(cents: amount, test: test)
        writeStatus()
        Log.write(String(format: "fed: +%.2f%@", Double(amount) / 100, test ? " (test)" : ""))
    }

    // MARK: - Sound

    private func playHit() {
        guard state.soundOn else { return }
        sounds.play(.hit)
    }

    // MARK: - Menus

    func buildMenu(into boxes: inout [ActionBox]) -> NSMenu {
        boxes.removeAll()
        let rootMenu = NSMenu()
        var menu = rootMenu
        menu.autoenablesItems = false
        menu.delegate = self

        func item(_ title: String, _ enabled: Bool = true, _ handler: @escaping () -> Void) -> NSMenuItem {
            let box = ActionBox(handler)
            boxes.append(box)
            let mi = NSMenuItem(title: title, action: #selector(ActionBox.fire(_:)), keyEquivalent: "")
            mi.target = box
            mi.isEnabled = enabled
            return mi
        }

        let status = NSMenuItem(title: model.connected
                                ? "余额 ¥\(model.realString)  ·  已连接"
                                : "余额 --  ·  \(model.lastError ?? model.statusText)",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if let src = model.credentialSource {
            let s = NSMenuItem(title: "凭证：" + src, action: nil, keyEquivalent: "")
            s.isEnabled = false
            menu.addItem(s)
        }
        if let spent = model.spentCny {
            let s = NSMenuItem(title: String(format: "累计消费 ¥%.2f", spent), action: nil, keyEquivalent: "")
            s.isEnabled = false
            menu.addItem(s)
        }
        menu.addItem(.separator())

        menu.addItem(item("立即刷新余额", schedule.canRefresh(at: CACurrentMediaTime())) { [weak self] in
            self?.poll(snap: true, force: true)
        })
        let demonstrations = NSMenu(title: "演示")
        demonstrations.autoenablesItems = false; demonstrations.delegate = self
        let demonstrationsItem = NSMenuItem(title: "演示", action: nil, keyEquivalent: "")
        demonstrationsItem.submenu = demonstrations; rootMenu.addItem(demonstrationsItem)
        menu = demonstrations
        menu.addItem(item("测试一次扣费") { [weak self] in self?.model.playOneHit() })
        menu.addItem(item("测试充值动画（+3.00）") { [weak self] in
            self?.props.spawnRice(amount: 3.0, test: true)
        })
        let radarInfo = NSMenuItem(title: "火控雷达：饭盆出现时自动显示", action: nil, keyEquivalent: "")
        radarInfo.isEnabled = false; menu.addItem(radarInfo)
        menu.addItem(item("自定义扣费次数…") { [weak self] in self?.askDemo(credit: false) })
        menu.addItem(item("自定义充值金额…") { [weak self] in self?.askDemo(credit: true) })


        let demo = NSMenuItem(title: "演示连续扣费", action: nil, keyEquivalent: "")
        let demoMenu = NSMenu(title: demo.title)
        demoMenu.autoenablesItems = false
        demoMenu.delegate = self
        for fen in [5, 10, 20, 50, 100] {
            let title = String(format: "-%.2f（%d 次）", Double(fen) / 100.0, fen)
            let box = ActionBox { [weak self] in self?.model.playDemo(times: fen) }
            boxes.append(box)
            let mi = NSMenuItem(title: title, action: #selector(ActionBox.fire(_:)), keyEquivalent: "")
            mi.target = box
            demoMenu.addItem(mi)
        }
        menu.addItem(demo)
        menu.setSubmenu(demoMenu, for: demo)

        let settings = NSMenu(title: "设置")
        settings.autoenablesItems = false; settings.delegate = self
        let settingsItem = NSMenuItem(title: "设置", action: nil, keyEquivalent: "")
        settingsItem.submenu = settings; rootMenu.addItem(settingsItem)
        menu = settings
        menu.addItem(item(self.state.bowlOnCredit ? "✓ 充值时掉米饭盆" : "　充值时掉米饭盆") { [weak self] in
            guard let self = self else { return }
            self.state.bowlOnCredit.toggle()
            self.model.suppressCreditFlourish = self.state.bowlOnCredit
            if !self.state.bowlOnCredit { self.props.removeAll(); self.model.forceSnapToReal() }
            self.state.save()
        })
        let characterMenu = NSMenu(title: "切换角色")
        characterMenu.autoenablesItems = false
        characterMenu.delegate = self
        for character in PetCharacter.allCases {
            let choice = item(character.displayName, PetAssets.sprite(for: character) != nil) { [weak self] in
                self?.setCharacter(character)
            }
            choice.state = (character == state.character) ? .on : .off
            characterMenu.addItem(choice)
        }
        let characterItem = NSMenuItem(title: characterMenu.title, action: nil, keyEquivalent: "")
        menu.addItem(characterItem)
        menu.setSubmenu(characterMenu, for: characterItem)

        let sizeMenu = NSMenu(title: "尺寸")
        sizeMenu.autoenablesItems = false
        sizeMenu.delegate = self
        for (i, preset) in Self.sizePresets.enumerated() {
            let box = ActionBox { [weak self] in self?.setSize(index: i) }
            boxes.append(box)
            let mi = NSMenuItem(title: "\(preset.title)（\(Int(preset.side))pt）",
                                action: #selector(ActionBox.fire(_:)), keyEquivalent: "")
            mi.target = box
            mi.state = (i == state.sizeIndex) ? .on : .off
            sizeMenu.addItem(mi)
        }
        let sizeItem = NSMenuItem(title: "尺寸", action: nil, keyEquivalent: "")
        menu.addItem(sizeItem)
        menu.setSubmenu(sizeMenu, for: sizeItem)

        menu.addItem(item(state.snapOnRelease ? "✓ 自动回到所选底角" : "　自动回到所选底角") { [weak self] in
            guard let self = self else { return }
            self.state.snapOnRelease.toggle()
            self.state.save()
        })
        menu.addItem(item(state.soundOn ? "✓ 音效" : "　音效") { [weak self] in
            guard let self = self else { return }
            self.state.soundOn.toggle()
            self.sounds.enabled = self.state.soundOn
            self.state.save()
        })

        menu.addItem(item(state.patEnabled ? "✓ 划动摸头" : "　划动摸头") { [weak self] in
            guard let self = self else { return }; self.state.patEnabled.toggle(); self.state.save()
        })
        menu.addItem(item(state.hurtEffects ? "✓ 扣费动画" : "　扣费动画") { [weak self] in
            guard let self = self else { return }; self.state.hurtEffects.toggle()
            self.model.hurtEffects = self.state.hurtEffects; self.state.save()
        })
        menu.addItem(item(state.mirrored ? "吸附到左下角" : "吸附到右下角") { [weak self] in
            guard let self = self else { return }; self.state.mirrored.toggle()
            self.view.mirrored = self.state.mirrored; self.view.needsDisplay = true
            self.snapToCorner(animated: false); self.props.resizeProps(); self.state.save()
        })
        let audioMenu = NSMenu(title: "各项音量")
        for (index, cue) in PetSound.allCases.enumerated() {
            let titles = ["扣费", "喂饭", "扣盆", "取盆"]
            let sub = NSMenu(title: titles[index])
            for level in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0] {
                let choice = item("\(Int(level*100))%") { [weak self] in
                    guard let self = self else { return }; self.state.cueVolumes[index] = level
                    self.sounds.volumes = self.state.cueVolumes.map { Float($0) }; self.sounds.play(cue); self.state.save()
                }
                choice.state = abs(state.cueVolumes[index]-level)<0.01 ? .on : .off
                sub.addItem(choice)
            }
            sub.addItem(.separator())
            sub.addItem(item("选择自定义音效…") { [weak self] in self?.chooseSound(cue) })
            sub.addItem(item("恢复原版音效") { [weak self] in
                try? FileManager.default.removeItem(at: SoundBank.customURL(for: cue))
                self?.sounds.preload(); self?.sounds.play(cue)
            })
            let row = NSMenuItem(title: titles[index], action: nil, keyEquivalent: ""); row.submenu = sub; audioMenu.addItem(row)
        }
        let audioItem = NSMenuItem(title: audioMenu.title, action: nil, keyEquivalent: ""); audioItem.submenu = audioMenu; menu.addItem(audioItem)
        menu.addItem(item("切换平板消费读数（也可双击平板）") { [weak self] in self?.toggleTariff() })
        menu.addItem(item("清理桌面上的饭盆和铁盆") { [weak self] in
            self?.props.removeAll(); self?.model.forceSnapToReal(); self?.view.needsDisplay = true
        })
        let intervalMenu = NSMenu(title: "刷新间隔")
        intervalMenu.autoenablesItems = false
        intervalMenu.delegate = self
        for seconds in [10.0, 30.0, 60.0, 300.0] {
            let title = seconds < 60 ? "\(Int(seconds)) 秒" : "\(Int(seconds / 60)) 分钟"
            let box = ActionBox { [weak self] in
                guard let self = self else { return }
                self.state.pollSeconds = seconds
                self.schedule.setInterval(seconds, at: CACurrentMediaTime())
                self.state.save()
            }
            boxes.append(box)
            let mi = NSMenuItem(title: title, action: #selector(ActionBox.fire(_:)), keyEquivalent: "")
            mi.target = box
            mi.state = (abs(seconds - state.pollSeconds) < 0.5) ? .on : .off
            intervalMenu.addItem(mi)
        }
        let intervalItem = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        menu.addItem(intervalItem)
        menu.setSubmenu(intervalMenu, for: intervalItem)

        menu.addItem(.separator())
        menu = rootMenu
        menu.addItem(.separator())
        menu.addItem(item("设置 API Key…") { [weak self] in self?.askForKey() })
        menu.addItem(item("重新读取凭证") { [weak self] in self?.reloadCredential() })
        menu.addItem(item("吸附回左下角") { [weak self] in
            self?.returnToLeftCorner()
        })
        menu.addItem(item("打开日志") {
            NSWorkspace.shared.open(PetPaths.logURL)
        })
        menu.addItem(item("打开配置文件夹") {
            NSWorkspace.shared.open(PetPaths.support)
        })
        menu.addItem(.separator())
        menu.addItem(item("退出") { NSApp.terminate(nil) })

        return menu
    }

    func showContextMenu(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        isMenuTracking = true
        window.ignoresMouseEvents = false
        defer { isMenuTracking = false }
        let menu = buildMenu(into: &popupBoxes)
        // A tiny borderless host must not constrain the menu's available space.
        // Position independently in screen coordinates at the original click.
        let location = window.convertPoint(toScreen: event.locationInWindow)
        menu.popUp(positioning: nil, at: location, in: nil)
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "yensign.circle.fill", accessibilityDescription: "DSH 余额") {
                button.image = img
            } else {
                button.title = "¥"
            }
            button.toolTip = "DSH 余额桌宠"
        }
        item.menu = buildMenu(into: &statusBoxes)
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        let fresh = buildMenu(into: &statusBoxes)
        menu.removeAllItems()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }

    // Menu structure must stay unchanged in AppKit's open/close callbacks.
    func menuWillOpen(_ menu: NSMenu) {
        if menu.supermenu == nil { isMenuTracking = true }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu.supermenu == nil { isMenuTracking = false }
    }

    func confinementRect(for menu: NSMenu, on screen: NSScreen?) -> NSRect {
        screen?.visibleFrame ?? .zero
    }

    func toggleTariff() { tariffMode.toggle(); updateTariff() }
    private func updateTariff() {
        view?.tariff = tariffMode ? (Double(usage.todayCents)/100, usage.hourlyRate) : nil
        view?.needsDisplay = true
    }

    // MARK: - Actions

    private func setCharacter(_ character: PetCharacter) {
        guard character != state.character, PetAssets.sprite(for: character) != nil else { return }
        state.character = character
        view.setCharacter(character)
        // Switching artwork leaves the balance model, queued animations, polling,
        // position and size intact. The next pointer tick uses the new alpha mask.
        state.save()
        writeStatus()
    }

    private func setSize(index: Int) {
        state.sizeIndex = min(max(index, 0), Self.sizePresets.count - 1)
        let newSize = PetLayout.windowSize(side: side)
        let origin = window.frame.origin
        window.setFrame(NSRect(origin: origin, size: newSize), display: true)
        props.resizeProps()
        keepWindowVisible()
        state.windowOrigin = window.frame.origin
        state.save()
    }

    private func reloadCredential() {
        props.removeAll()
        usage.resetBaseline()
        credential = CredentialStore.resolve()
        schedule.reload(at: CACurrentMediaTime())
        model.resetForCredentialChange()
        model.setCredentialSource(credentialSourceLabel())
        if credential == nil {
            model.setNoCredential()
        }
        view.needsDisplay = true
        poll(snap: true)
        Log.write("credential reloaded: \(credential?.shortDescription ?? "none")")
    }

    private func askDemo(credit: Bool) {
        let alert = NSAlert()
        alert.messageText = credit ? "模拟充值金额（元）" : "模拟扣费次数（1–500）"
        let field = NSTextField(string: credit ? "3.00" : "10")
        field.frame = CGRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "播放"); alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if credit, let amount = Double(field.stringValue), amount.isFinite, amount >= 0.01, amount <= 1_000_000 {
            props.spawnRice(amount: amount, test: true)
        } else if !credit, let count = Int(field.stringValue), (1...500).contains(count) {
            model.playDemo(times: count)
        }
    }

    private func chooseSound(_ cue: PetSound) {
        let panel = NSOpenPanel()
        panel.title = "选择音效（60 秒以内，20 MB 以内）"
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard bytes <= 20_000_000 else { throw SoundImportError.invalid }
            let data = try Data(contentsOf: url)
            guard let audio = NSSound(data: data), audio.duration.isFinite, audio.duration > 0, audio.duration <= 60 else {
                throw SoundImportError.invalid
            }
            let output = SoundBank.customURL(for: cue)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: output, options: .atomic)
            sounds.preload(); sounds.play(cue)
        } catch {
            let alert = NSAlert(); alert.messageText = "请选择可播放、60 秒以内且不超过 20 MB 的音频"
            alert.runModal()
        }
    }

    private enum SoundImportError: Error { case invalid }

    private func askForKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "设置 DeepSeek API Key"
        alert.informativeText = """
        填入 sk- 开头的 DeepSeek API Key，会保存到：
        \(PetPaths.userKeyURL.path)

        留空直接点「保存」不会改动当前凭证。
        如果设置了 DSHPET_KEY 环境变量或应用目录 apikey.txt，它们优先于此处保存的 Key。
        """
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "sk-..."
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            do {
                try CredentialStore.saveAPIKey(value, to: PetPaths.userKeyURL)
                reloadCredential()
            } catch {
                let failure = NSAlert()
                failure.messageText = "API Key 未保存"
                failure.informativeText = error.localizedDescription
                failure.alertStyle = .warning
                failure.runModal()
            }
        }
    }
}
