import AppKit

// Head-less modes first so they never open a window.
if Diagnostics.wantsRun() {
    exit(Diagnostics.run())
}

do {
    let instance = try InstanceLock(directory: PetPaths.support)
    let app = NSApplication.shared
    let controller = PetController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    withExtendedLifetime((instance, controller)) { app.run() }
} catch {
    fputs("无法启动桌宠：同一配置目录可能已有实例运行，或配置目录无法写入。\n", stderr)
    exit(1)
}
