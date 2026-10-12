import SwiftUI
import AppKit

@main
struct TotpupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var vault: Vault
    init() {
        let arguments = CommandLine.arguments
        let preview = arguments.contains("--render-preview") || arguments.contains("--render-icon") || arguments.contains("--render-popup") || arguments.contains("--render-settings") || arguments.contains("--check-surfaces")
        let vault = Vault(preview: preview || arguments.contains("--check-startup"))
        _vault = StateObject(wrappedValue: vault)
        AppRuntime.isPreview = preview || arguments.contains("--render-icon")
        if !AppRuntime.isPreview {
            NSApplication.shared.setActivationPolicy(.accessory)
            AppRuntime.surfaces = SurfaceCoordinator(vault: vault)
        }
        if arguments.contains("--check-surfaces") {
            SurfaceCoordinator(vault: vault).verifyPanelReuse()
            exit(0)
        }
        if preview {
            let path = arguments.last ?? "/tmp/totpup-preview.png"
            let icon = arguments.contains("--render-icon")
            let popup = arguments.contains("--render-popup")
            let settings = arguments.contains("--render-settings")
            let content: AnyView = settings ? AnyView(SettingsView(vault: vault).background(ThemeBackground())) : icon
                ? AnyView(PupView(awake: true, celebrate: false, animate: false).frame(width: 130, height: 135).scaleEffect(3.6).frame(width: 512, height: 512))
                : (popup ? AnyView(QuickFetchView(vault: vault, notch: true, openDen: {}, close: {}).frame(width: 360, height: 270))
                    : AnyView(DenView(vault: vault, compact: false).frame(width: 410, height: 520)))
            let host = NSHostingView(rootView: content)
            let rectangle = NSRect(x: 0, y: 0, width: settings ? 410 : (icon ? 512 : (popup ? 360 : 410)), height: settings ? 520 : (icon ? 512 : (popup ? 270 : 520)))
            let window = NSWindow(contentRect: rectangle, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = host
            host.frame = rectangle
            host.layoutSubtreeIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: rectangle) {
                host.cacheDisplay(in: rectangle, to: bitmap)
                if icon {
                    precondition(bitmap.hasAlpha, "The app icon must preserve transparency")
                    for (x, y) in [(0, 0), (bitmap.pixelsWide - 1, 0), (0, bitmap.pixelsHigh - 1), (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)] {
                        precondition(bitmap.colorAt(x: x, y: y)?.alphaComponent == 0, "The app icon corners must be transparent")
                    }
                    print("Verified transparent app icon: alpha channel and four clear corners.")
                }
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    do { try png.write(to: URL(fileURLWithPath: path)); print("Rendered demo preview: \(path)"); exit(0) }
                    catch { print("Preview couldn’t be saved."); exit(1) }
                }
            }
            print("Preview couldn’t be rendered."); exit(1)
        }
    }
    var body: some Scene {
        Window("Totpup", id: "den") {
            DenView(vault: vault, compact: false)
                .frame(minWidth: 390, idealWidth: 410, maxWidth: 520, minHeight: 460, idealHeight: 520)
                .background(WindowReader())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 410, height: 520)
        .commands { CommandGroup(replacing: .newItem) { Button("Add account") { vault.showAdd = true }.keyboardShortcut("n") } }

    }
}

struct WindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let identifier = NSUserInterfaceItemIdentifier("totpup.den")
            if window.identifier != identifier {
                window.identifier = identifier
                window.setContentSize(NSSize(width: 410, height: 520))
            }
            if !window.isMovableByWindowBackground { window.isMovableByWindowBackground = true }
            let color = NSColor(Palette.background)
            if !window.isOpaque { window.isOpaque = true }
            if window.backgroundColor != color { window.backgroundColor = color }
            AppRuntime.refreshDock()
        }
    }
}
