import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor enum AppRuntime {
    static var surfaces: SurfaceCoordinator?
    static var openDen: (() -> Void)?
    static var isPreview = false
    static var previewDate: Date?
    private static var dockImage: NSImage?
    static func showDock() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        restoreDockImage()
        // Switching an accessory to a regular app creates a new Dock tile asynchronously.
        DispatchQueue.main.async { restoreDockImage() }
    }
    static func restoreDockImage() {
        guard !isPreview else { return }
        if dockImage == nil {
            let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png")
                ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            dockImage = url.flatMap { NSImage(contentsOf: $0) }
        }
        guard let image = dockImage else { return }
        NSApp.applicationIconImage = image
        if NSApp.activationPolicy() == .regular {
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: NSApp.dockTile.size))
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            NSApp.dockTile.contentView = imageView
            NSApp.dockTile.display()
        }
    }
    static func refreshDock(excluding closing: NSWindow? = nil) {
        let mainVisible = NSApp.windows.contains {
            $0 !== closing && $0.identifier?.rawValue == "totpup.den" && ($0.isVisible || $0.isMiniaturized)
        }
        let policy: NSApplication.ActivationPolicy = mainVisible || surfaces?.isPopupVisible == true ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            if policy == .regular { showDock() }
            else { NSApp.setActivationPolicy(.accessory) }
        }
    }
    static func revealDen() {
        showDock()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "totpup.den" }) {
            window.makeKeyAndOrderFront(nil)
        } else { openDen?() }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObservers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppRuntime.isPreview else { return }
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
                let closing = name == NSWindow.willCloseNotification ? notification.object as? NSWindow : nil
                Task { @MainActor in AppRuntime.refreshDock(excluding: closing) }
            }
            windowObservers.append(observer)
        }
        AppRuntime.restoreDockImage()
        AppRuntime.surfaces?.start()
        AppRuntime.refreshDock()
        if CommandLine.arguments.contains("--check-startup") { verifyLiveStartup() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppRuntime.revealDen()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "totpup" && $0.host == "den" }) { AppRuntime.revealDen(); return }
        guard urls.contains(where: { $0.scheme == "totpup" && $0.host == "fetch" }) else { return }
        // Deep links remain usable even if the keyboard shortcut is disabled.
        AppRuntime.surfaces?.showPopup(fromWidget: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        AppRuntime.surfaces?.vault.lock()
        AppRuntime.surfaces?.stop()
    }
    private func verifyLiveStartup() {
        let startedAt = ProcessInfo.processInfo.systemUptime
        // Exercise the real Scene lifecycle and MenuBarExtra insertion updates.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let surfaces = AppRuntime.surfaces else { fatalError("Missing surface controller") }
            precondition(ProcessInfo.processInfo.systemUptime - startedAt < 5, "Launch starved the main event loop")
            surfaces.vault.menuBarEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                surfaces.vault.menuBarEnabled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    precondition(ProcessInfo.processInfo.systemUptime - startedAt < 9, "Menu bar reinsertion starved the main event loop")
                    AppRuntime.revealDen(); AppRuntime.revealDen()
                    surfaces.verifyPanelReuse()
                    let mainWindows = NSApp.windows.filter { $0.identifier?.rawValue == "totpup.den" }
                    precondition(mainWindows.count == 1, "Opening the den repeatedly created duplicate main windows")
                    precondition(NSApp.activationPolicy() == .regular, "Visible den must show the Dock icon")
                    mainWindows.forEach { $0.orderOut(nil) }
                    AppRuntime.refreshDock()
                    precondition(NSApp.activationPolicy() == .accessory, "Background app must hide the Dock icon")
                    surfaces.showPopup(fromWidget: true)
                    precondition(NSApp.activationPolicy() == .regular, "Popup must show the Dock icon")
                    surfaces.dismissPopup()
                    precondition(NSApp.activationPolicy() == .accessory, "Closing popup must hide the Dock icon")
                    surfaces.verifyStatusItem()
                    print("Passed live startup checks: responsive event loop, menu bar removal/reinsertion, one main window, and background/popup Dock transitions.")
                    surfaces.stop()
                    exit(0)
                }
            }
        }
    }
}

private final class PeekPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class SurfaceCoordinator: NSObject, NSWindowDelegate {
    let vault: Vault
    private var hoverTimer: Timer?
    private var notchPanel: PeekPanel?
    private var popupPanel: PeekPanel?
    private var closeTask: Task<Void, Never>?
    private var wasInTrigger = false
    private var hideAt = Date.distantFuture
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var hotKeySubscription: AnyCancellable?
    private var statusSubscription: AnyCancellable?
    private var statusItem: NSStatusItem?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var started = false
    private var restoringPopup = false
    var isPopupVisible: Bool { popupPanel?.isVisible == true }
    func refreshStatusItem() { configureStatusItem(vault.menuBarEnabled) }

    init(vault: Vault) { self.vault = vault; super.init() }
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === popupPanel, !restoringPopup,
              !AppRuntime.isPreview, !CommandLine.arguments.contains("--check-startup") else { return }
        UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: "popupOrigin")
    }
    func start() {
        guard !started else { return }; started = true
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if self?.popupPanel?.isVisible == true { self?.resizePopupIfNeeded() }
                self?.checkHover(); AppRuntime.refreshDock()
            }
        }
        let handler: EventHandlerUPP = { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<SurfaceCoordinator>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in if controller.vault.popupEnabled { controller.showPopup() } }
            return noErr
        }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &event,
            Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        hotKeySubscription = vault.$popupEnabled.removeDuplicates().sink { [weak self] enabled in self?.configureHotKey(enabled) }
        statusSubscription = vault.$menuBarEnabled.removeDuplicates().sink { [weak self] enabled in self?.configureStatusItem(enabled) }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismissPopupIfOutside() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.window !== self?.statusItem?.button?.window { self?.dismissPopupIfOutside() }
            return event
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismissPopup(); self?.dismissNotch() }
            return event
        }
    }
    func stop() {
        hoverTimer?.invalidate(); hoverTimer = nil
        closeTask?.cancel()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        hotKeySubscription?.cancel(); hotKeySubscription = nil
        statusSubscription?.cancel(); statusSubscription = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem); self.statusItem = nil }
        for monitor in [globalClickMonitor, localClickMonitor, localKeyMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        notchPanel?.orderOut(nil); popupPanel?.orderOut(nil); started = false
    }
    private func configureStatusItem(_ enabled: Bool) {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem); self.statusItem = nil }
        guard enabled else { return }
        let item = NSStatusBar.system.statusItem(withLength: 26)
        item.autosaveName = "TotpupStatusItem"
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Totpup")
        item.button?.image?.size = NSSize(width: 18, height: 18)
        item.button?.image?.isTemplate = true
        item.isVisible = true
        item.button?.toolTip = "Totpup — click to fetch a code. Right-click for app options."
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }
    func verifyStatusItem() {
        precondition(statusItem?.isVisible == true, "Menu bar item must be enabled")
        precondition(statusItem?.button?.image != nil, "Menu bar item must have its paw image")
        precondition(statusItem?.button?.window != nil, "Menu bar item must have a native host window")
        if let frame = statusItem?.button?.window?.frame {
            print("Menu bar paw host frame: \(NSStringFromRect(frame)). macOS may hide it when the menu bar is full.")
        }
    }
    @objc private func statusClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp, let button = statusItem?.button {
            let menu = NSMenu()
            let den = NSMenuItem(title: "Open Totpup", action: #selector(openDenFromStatus), keyEquivalent: "")
            den.target = self; menu.addItem(den); menu.addItem(.separator())
            let quit = NSMenuItem(title: "Quit Totpup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp; menu.addItem(quit)
            NSMenu.popUpContextMenu(menu, with: event, for: button)
            return
        }
        if popupPanel?.isVisible == true { dismissPopup(); return }
        let anchor = statusItem?.button?.window.map { NSPoint(x: $0.frame.midX, y: $0.frame.minY - 8) }
        showPopup(fromWidget: true, anchor: anchor)
    }
    @objc private func openDenFromStatus() { AppRuntime.revealDen() }
    private func configureHotKey(_ enabled: Bool) {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        guard enabled else { return }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x50555050, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { vault.error = "Control + Option + P is already in use. You can still open the popup from Totpup or its widget." }
    }
    func verifyPanelReuse() {
        showPopup(fromWidget: true)
        let firstPopup = popupPanel
        let movedOrigin = NSPoint(x: firstPopup!.frame.minX + 12, y: firstPopup!.frame.minY - 12)
        firstPopup?.setFrameOrigin(movedOrigin)
        showPopup(fromWidget: true)
        precondition(firstPopup === popupPanel, "Repeated popup actions must reuse one panel")
        precondition(popupPanel?.frame.origin == movedOrigin, "Reopening must preserve the popup's moved position")
        precondition(popupPanel?.isMovableByWindowBackground == true, "Popup must support native window dragging")
        precondition(popupPanel?.frame.width == 360, "Popup must remain compact")
        dismissPopup()
        guard let screen = NSScreen.main else { fatalError("No screen available for panel validation") }
        showNotch(on: screen)
        let firstNotch = notchPanel
        showNotch(on: screen)
        precondition(firstNotch === notchPanel, "Repeated notch peeks must reuse one panel")
        precondition(notchPanel !== popupPanel, "Notch and popup must be independent surfaces")
        precondition(notchPanel?.frame.width == 360, "Notch peek must remain compact")
        notchPanel?.orderOut(nil)
        print("Passed 7 native surface checks: popup reuse, drag support, position retention, notch reuse, independent panels, and compact dimensions.")
    }
    private func panel(width: CGFloat, height: CGFloat, notch: Bool) -> PeekPanel {
        let panel = PeekPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.level = notch ? .statusBar : .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = !notch
        if !notch { panel.delegate = self }
        panel.contentView = NSHostingView(rootView: QuickFetchView(vault: vault, notch: notch, openDen: {
            self.dismissPopup(); self.dismissNotch(); AppRuntime.revealDen()
        }, close: { if notch { self.dismissNotch() } else { self.dismissPopup() } }))
        return panel
    }
    func showPopup(fromWidget: Bool = false, anchor: NSPoint? = nil) {
        guard vault.popupEnabled || fromWidget else { return }
        let isNew = popupPanel == nil
        let size = codePanelSize
        if isNew { popupPanel = panel(width: size.width, height: size.height, notch: false) }
        else { resizePopupIfNeeded() }
        guard let panel = popupPanel,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let centered: NSPoint
        if let anchor {
            centered = NSPoint(x: min(max(anchor.x - panel.frame.width / 2, frame.minX), frame.maxX - panel.frame.width),
                y: min(max(anchor.y - panel.frame.height, frame.minY), frame.maxY - panel.frame.height))
        } else { centered = NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2) }
        if isNew {
            let saved = UserDefaults.standard.string(forKey: "popupOrigin").map(NSPointFromString)
            let savedFrame = NSRect(origin: saved ?? centered, size: panel.frame.size)
            let visible = NSScreen.screens.contains { $0.visibleFrame.contains(savedFrame) }
            restoringPopup = true
            panel.setFrameOrigin(visible ? savedFrame.origin : centered)
            restoringPopup = false
        } else if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            restoringPopup = true; panel.setFrameOrigin(centered); restoringPopup = false
        }
        AppRuntime.showDock()
        panel.makeKeyAndOrderFront(nil)
        AppRuntime.refreshDock()
    }
    private var codePanelSize: NSSize {
        let single = !vault.locked && vault.ready && vault.accounts.count == 1
        return NSSize(width: single ? 300 : 360, height: single ? 185 : 270)
    }
    private func resizePopupIfNeeded() {
        guard let panel = popupPanel, panel.frame.size != codePanelSize else { return }
        let size = codePanelSize
        var origin = NSPoint(x: panel.frame.minX, y: panel.frame.maxY - size.height)
        if let screen = panel.screen ?? NSScreen.main {
            let bounds = screen.visibleFrame
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        }
        restoringPopup = true
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        restoringPopup = false
    }
    func dismissPopup() { popupPanel?.orderOut(nil); AppRuntime.refreshDock() }
    private func dismissPopupIfOutside() {
        guard let panel = popupPanel, panel.isVisible, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        dismissPopup()
    }
    private func checkHover() {
        guard vault.notchEnabled else { wasInTrigger = false; dismissNotch(); return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return }
        let topInset = screen.safeAreaInsets.top
        let notchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(180, screen.frame.width - left.width - right.width)
        } else { notchWidth = 180 }
        let trigger = NSRect(x: screen.frame.midX - notchWidth / 2 - 12,
            y: screen.frame.maxY - max(topInset, 24) - 10, width: notchWidth + 24, height: max(topInset, 24) + 10)
        let inTrigger = trigger.contains(mouse)
        if inTrigger && !wasInTrigger && notchPanel?.isVisible != true { showNotch(on: screen) }
        wasInTrigger = inTrigger
        if let panel = notchPanel, panel.isVisible {
            let destination = notchFrame(on: screen)
            if panel.frame.size != destination.size { panel.setFrame(destination, display: true) }
            if panel.frame.contains(mouse) { hideAt = Date().addingTimeInterval(TimeInterval(vault.notchDuration)) }
            else if Date() >= hideAt { dismissNotch() }
        }
    }
    private func notchFrame(on screen: NSScreen) -> NSRect {
        let size = codePanelSize
        return NSRect(x: screen.frame.midX - size.width / 2,
                      y: screen.frame.maxY - max(screen.safeAreaInsets.top, 24) - size.height,
                      width: size.width, height: size.height)
    }
    private func showNotch(on screen: NSScreen) {
        let destination = notchFrame(on: screen)
        if notchPanel == nil { notchPanel = panel(width: destination.width, height: destination.height, notch: true) }
        guard let panel = notchPanel else { return }
        closeTask?.cancel(); hideAt = Date().addingTimeInterval(TimeInterval(vault.notchDuration))
        panel.setFrame(destination.offsetBy(dx: 0, dy: 18), display: false)
        panel.alphaValue = 0; panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = vault.playful && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.24 : 0
            panel.animator().alphaValue = 1
            panel.animator().setFrame(destination, display: true)
        }
    }
    func dismissNotch() {
        guard let panel = notchPanel, panel.isVisible, closeTask == nil else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = vault.playful && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.18 : 0
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(NSPoint(x: panel.frame.minX, y: panel.frame.minY + 14))
        }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(190))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil); self?.closeTask = nil
        }
    }
}

struct QuickFetchView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var vault: Vault
    var notch: Bool
    var openDen: () -> Void
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack {
                    Image(systemName: "pawprint.fill").foregroundStyle(Palette.orange)
                    Text("totpup").font(.system(size: 19, weight: .heavy, design: .rounded))
                    Spacer()
                    Text(notch ? "A LITTLE PEEK" : "FETCH A CODE").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(Palette.muted)
                }.contentShape(Rectangle()).modifier(PopupHeaderDrag(enabled: !notch))
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }.buttonStyle(.plain).accessibilityLabel("Close popup")
            }.help(notch ? "Totpup notch peek" : "Drag this header to move the popup")
            if vault.locked {
                HStack {
                    PupView(awake: false, celebrate: false, animate: false).frame(width: 100, height: 115)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your pup is napping.").font(.system(size: 16, weight: .semibold, design: .rounded))
                        Button("Unlock your den", action: openDen).buttonStyle(PupButtonStyle())
                    }
                }
                Spacer(minLength: 0)
            } else if !vault.ready {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Couldn’t load accounts", systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.orange)
                    Text(vault.loadError ?? "Keychain access is unavailable.")
                        .font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let date = AppRuntime.previewDate ?? timeline.date
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(vault.displayed) { account in
                                Button { vault.copy(account) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(account.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                            Text(vault.code(account, at: date) ?? "———")
                                                .font(.system(size: 24, weight: .semibold, design: .monospaced)).tracking(3)
                                            UpcomingCodeView(account: account, vault: vault, date: date, animated: vault.playful)
                                        }
                                        Spacer()
                                        Text("\(account.configuration.remaining(at: date))s").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                                        Image(systemName: vault.copiedID == account.id ? "checkmark.circle.fill" : (account.isDemo ? "sparkles" : "doc.on.doc"))
                                            .foregroundStyle(vault.copiedID == account.id ? Palette.orange : Palette.muted)
                                    }.padding(10).background(.white.opacity(notch && !reduceTransparency ? 0.8 * (1 - vault.notchTransparency) : 0.8), in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).help(account.isDemo ? "Copy demo code — not a real account" : "Copy code")
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
            }
            HStack {
                Text(!vault.ready && !vault.locked ? "Keychain access needed" : (vault.copiedID != nil ? "Copied · clears in 20s" : (vault.error ?? (vault.accounts.isEmpty && !vault.locked ? "Demo accounts" : "Secrets stay in your den.")))).font(.system(size: 9)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Open den ↗", action: openDen).font(.system(size: 10, weight: .semibold)).buttonStyle(.plain)
            }
        }.padding(18).foregroundStyle(Palette.ink)
            .background(Palette.background.opacity(notch && !reduceTransparency ? 1 - vault.notchTransparency : 1), in: RoundedRectangle(cornerRadius: notch ? 23 : 26))
            .overlay(RoundedRectangle(cornerRadius: notch ? 23 : 26).stroke(Palette.ink.opacity(0.12)))
            .preferredColorScheme(.light)
    }
}

private struct PopupHeaderDrag: ViewModifier {
    var enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            if #available(macOS 15.0, *) { content.gesture(WindowDragGesture()) }
            else { content.background(LegacyWindowDragRegion()) }
        } else { content }
    }
}

private struct LegacyWindowDragRegion: NSViewRepresentable {
    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
