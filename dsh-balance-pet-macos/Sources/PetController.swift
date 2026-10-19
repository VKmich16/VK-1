import AppKit

final class ActionBox: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire(_ sender: Any?) { handler() }
}

final class PetController: NSObject, NSApplicationDelegate, NSMenuDelegate {

    let model = PetModel()
    private var view: PetView!
    private var window: PetWindow!
    private var statusItem: NSStatusItem?
    private var state = PetState.load()
    private var credential: Credential?

    private var tickTimer: Timer?
    private var lastFrame: CFTimeInterval = CACurrentMediaTime()
    private var schedule = PollSchedule(interval: 30)
    private var statusAccum: Double = 0
    private var wakeObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    private var statusBoxes: [ActionBox] = []
    private var popupBoxes: [ActionBox] = []
    private var isMenuTracking = false

    private var soundPlayers: [NSSound] = []
    private var soundIndex = 0

    static let sizePresets: [(title: String, side: CGFloat)] = [
        ("小", 110), ("中", 150), ("大", 210), ("特大", 280),
    ]

    private var side: CGFloat {
        let i = min(max(state.sizeIndex, 0), Self.sizePresets.count - 1)
        return Self.sizePresets[i].side
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        credential = CredentialStore.resolve()
        schedule = PollSchedule(interval: state.pollSeconds)

        if PetAssets.sprite(for: state.character) == nil {
            state.character = .deepseek
        }
        view = PetView(model: model, character: state.character)
        view.controller = self

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
        if let observer = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let observer = screenObserver { NotificationCenter.default.removeObserver(observer) }
        state.windowOrigin = window?.frame.origin
        state.save()
        if window != nil { writeStatus(running: false) }
    }

    // MARK: - Window placement

    private func placeWindow() {
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
        if !isOnScreen(origin: window.frame.origin, size: window.frame.size) {
            snapToCorner(animated: false)
            state.save()
        }
    }

    /// Snap to the bottom-left corner. `on` defaults to the screen the pet is
    /// currently sitting on, so dragging it to another display keeps it there.
    func snapToCorner(animated: Bool, on screen: NSScreen? = nil) {
        guard let target = screen ?? window.screen ?? NSScreen.main else { return }
        let vf = target.visibleFrame
        let origin = NSPoint(x: vf.minX + 14, y: vf.minY + 14)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrameOrigin(origin)
            }
        } else {
            window.setFrameOrigin(origin)
        }
        state.windowOrigin = origin
    }

    func dragDidEnd() {
        state.windowOrigin = window.frame.origin
        if state.snapOnRelease { snapToCorner(animated: true) }
        state.save()
    }

    // MARK: - Tick

    private func startTick() {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.frameTick() }
        t.tolerance = 0.005
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    private func frameTick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastFrame)
        lastFrame = now

        let wasAnimating = model.needsAnimationFrame
        model.tick(dt)
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
            writeStatus()
        }
    }

    /// Publish a small liveness/geometry snapshot so the pet can be inspected
    /// from another process without screen-recording permission.
    private func writeStatus(running: Bool = true) {
        let f = window.frame
        let obj: [String: Any] = [
            "running": running,
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
                    if snap || wasDisconnected {
                        self.model.apply(reading: reading, snap: true)
                    } else {
                        self.model.apply(reading: reading, snap: false)
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

    // MARK: - Sound

    private func playHit() {
        guard state.soundOn, let url = PetPaths.soundURL else { return }
        // All players and indexes are owned by the main thread.
        if soundPlayers.isEmpty {
            for _ in 0..<4 {
                if let s = NSSound(contentsOf: url, byReference: true) {
                    s.volume = 0.7
                    soundPlayers.append(s)
                }
            }
        }
        guard !soundPlayers.isEmpty else { return }
        let player = soundPlayers[soundIndex]
        soundIndex = (soundIndex + 1) % soundPlayers.count
        player.stop()
        player.play()
    }

    // MARK: - Menus

    private func buildMenu(into boxes: inout [ActionBox]) -> NSMenu {
        boxes.removeAll()
        let menu = NSMenu()
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
        menu.addItem(item("测试一次扣费") { [weak self] in self?.model.playOneHit() })

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

        menu.addItem(item(state.snapOnRelease ? "✓ 松手吸附左下角" : "　松手吸附左下角") { [weak self] in
            guard let self = self else { return }
            self.state.snapOnRelease.toggle()
            self.state.save()
        })
        menu.addItem(item(state.soundOn ? "✓ 音效" : "　音效") { [weak self] in
            guard let self = self else { return }
            self.state.soundOn.toggle()
            if !self.state.soundOn { self.soundPlayers.forEach { $0.stop() } }
            self.state.save()
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
        menu.addItem(item("设置 API Key…") { [weak self] in self?.askForKey() })
        menu.addItem(item("重新读取凭证") { [weak self] in self?.reloadCredential() })
        menu.addItem(item("吸附回左下角") { [weak self] in
            self?.snapToCorner(animated: true)
            self?.state.save()
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
        keepWindowVisible()
        state.windowOrigin = window.frame.origin
        state.save()
    }

    private func reloadCredential() {
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
