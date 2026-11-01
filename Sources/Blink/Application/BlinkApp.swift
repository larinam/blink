import AppKit
import BlinkCore
import SwiftUI

@main
enum BlinkApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let store = StateStore()
        do {
            // Acquire before AppModel can load, modify or save any shared state.
            let lease = try StateDirectoryLock(directory: store.directory)
            let delegate = AppDelegate(store: store)
            application.delegate = delegate
            withExtendedLifetime((delegate, lease)) { application.run() }
        } catch {
            let alert = NSAlert()
            if case StateDirectoryLock.Failure.alreadyRunning = error {
                alert.messageText = "Blink is already running"
                alert.informativeText = "Another copy of Blink is using your saved data. Quit that copy before opening this one."
            } else {
                alert.messageText = "Blink couldn’t open its saved data"
                alert.informativeText = "Blink couldn’t safely access its data folder. \(error.localizedDescription)"
            }
            alert.addButton(withTitle: "OK")
            application.activate()
            alert.runModal()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store: StateStore
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var mainWindow: NSWindow?
    private var windowSession: AppWindowSession?
    private var onboardingWindow: NSWindow?
    private let globalShortcut = GlobalShortcut()

    init(store: StateStore = StateStore()) {
        self.store = store
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        model = AppModel(store: store)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Blink eye care")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Blink eye care")
        }
        popover.behavior = .transient
        popover.delegate = self
        let hosting = NSHostingController(rootView: MenuView(model: model,
            openPage: { [weak self] in self?.showPage($0) },
            close: { [weak self] in self?.popover.performClose(nil) },
            quit: { NSApplication.shared.terminate(nil) }).fixedSize())
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        model.onChange = { [weak self] in self?.updateStatus() }
        model.hasVisibleCountdown = { [weak self] in self?.popover.isShown == true }
        model.onOpenPage = { [weak self] in self?.showPage($0) }
        model.onOnboardingFinished = { [weak self] in
            self?.onboardingWindow?.orderOut(nil)
            self?.onboardingWindow = nil
            self?.showPopover()
        }
        model.start()
        model.globalShortcutDescription = globalShortcut.description
        globalShortcut.onDescriptionChange = { [weak self] description in
            self?.model.globalShortcutDescription = description
        }
        model.globalShortcutAvailable = globalShortcut.start { [weak self] in
            guard let self else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
            if model.snapshot.settings.onboardingComplete { showPopover() } else { showOnboarding() }
        }
        updateStatus()
        if !model.snapshot.settings.onboardingComplete { showOnboarding() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalShortcut.stop()
        model?.stop()
    }
    func applicationDidBecomeActive(_ notification: Notification) { model?.refreshLoginStatus() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.snapshot.settings.onboardingComplete { showPopover() } else { showOnboarding() }
        return false
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.tick(forceInterface: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            let window = makeWindow(title: "Welcome to Blink", size: NSSize(width: 650, height: 705), resizable: false)
            window.contentView = NSHostingView(rootView: OnboardingView(model: model))
            onboardingWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func showPage(_ page: AppPage) {
        popover.performClose(nil)
        if !model.snapshot.settings.onboardingComplete && page != .feedback { showOnboarding(); return }
        if mainWindow == nil {
            let session = AppWindowSession(settings: model.snapshot.settings, selection: page)
            windowSession = session
            mainWindow = makeWindow(title: "Blink", size: NSSize(width: 850, height: 720), resizable: true)
            mainWindow?.minSize = NSSize(width: 850, height: 708)
            mainWindow?.contentView = NSHostingView(rootView: AppWindowView(model: model, session: session))
        }
        windowSession?.selection = page
        model.refreshLoginStatus()
        NSApplication.shared.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(title: String, size: NSSize, resizable: Bool) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func updateStatus() {
        let status = model.snapshot.status
        let symbol = status == .quiet ? "eye.slash" : status == .onBreak ? "sun.horizon" : "eye"
        if statusItem.button?.image?.name() != NSImage.Name(symbol) {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Blink eye care")
            image?.isTemplate = true
            image?.setName(symbol)
            statusItem.button?.image = image
        }
        let detail: String
        switch status {
        case .quiet:
            detail = model.snapshot.quietUntil.map { "Quiet until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Quiet until resumed"
        case .idle: detail = "Away · timers paused"
        case .onBreak: detail = "Break in progress"
        case .onboarding: detail = "Set up your eye care reminders"
        case .running:
            if model.snapshot.pendingBreak != nil { detail = "Your break is ready" }
            else if let next = model.snapshot.nextScheduledBreak {
                detail = "Next \(next.title.lowercased()) in about \(ceil(model.snapshot.remaining(for: next) / 60).formatted(.number.precision(.fractionLength(0)))) minutes"
            } else { detail = model.snapshot.settings.blinkEnabled ? "Blink cues are running" : "Reminders are off" }
        }
        statusItem.button?.toolTip = "Blink · \(detail)"
        statusItem.button?.setAccessibilityValue(detail)
    }

    private func buildMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Blink", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Show Current Reminder", action: #selector(showCurrentReminder), keyEquivalent: "r")
            .keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(withTitle: "Start Eye Break", action: #selector(startEyeBreak), keyEquivalent: "b")
            .keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(withTitle: "Start Movement Break", action: #selector(startMovementBreak), keyEquivalent: "m")
            .keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(withTitle: "Start Long Break", action: #selector(startLongBreak), keyEquivalent: "l")
            .keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Blink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit
        menu.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApplication.shared.mainMenu = menu
    }

    @objc private func openSettings() { showPage(.settings) }
    /// Packaged downloads record their channel and source revision; show them beside the build number.
    @objc private func showAbout() {
        let info = Bundle.main.infoDictionary ?? [:]
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let build = info["CFBundleVersion"] as? String, let revision = info["BlinkSourceRevision"] as? String {
            let channel = info["BlinkChannel"] as? String == "development" ? "Development · " : ""
            options[.version] = "\(build) · \(channel)\(revision.prefix(7))"
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }
    @objc private func showCurrentReminder() {
        model.tick(forceInterface: true)
        if model.snapshot.pendingBreak != nil { model.overlays.focusPrompt() } else { showPopover() }
    }
    @objc private func startEyeBreak() { model.startBreak(.short) }
    @objc private func startMovementBreak() {
        if model.snapshot.settings.movementEnabled { model.startBreak(.movement) }
        else { showPage(.settings) }
    }
    @objc private func startLongBreak() { model.startBreak(.long) }
}
