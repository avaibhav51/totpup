import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Renders the real views using demo data only; never loads Keychain or writes preferences.
@MainActor enum DocumentationMedia {
    enum Scene { case accounts, upcoming, popup, settings, locked }

    static func export(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let shots: [(Scene, String)] = [(.accounts, "accounts.png"), (.upcoming, "upcoming-code.png"),
            (.popup, "compact-popup.png"), (.settings, "settings.png"), (.locked, "locked.png")]
        for (scene, name) in shots {
            let bitmap = capture(scene: scene, second: scene == .upcoming ? 5 : 0, walkthrough: false)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: directory.appendingPathComponent(name))
        }
        let file = directory.appendingPathComponent("totpup-demo.gif")
        guard let gif = CGImageDestinationCreateWithURL(file as CFURL, UTType.gif.identifier as CFString, 26, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<26 {
            let scene: Scene = index < 12 ? .accounts : (index < 17 ? .popup : (index < 22 ? .settings : .locked))
            let bitmap = capture(scene: scene, second: index < 12 ? index : 5, walkthrough: true)
            guard let cgImage = bitmap.cgImage else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(gif, cgImage, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.5]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw CocoaError(.fileWriteUnknown) }
        AppRuntime.previewDate = nil
        print("Exported 5 demo screenshots and a 13-second animated walkthrough to \(directory.path)")
    }

    private static func capture(scene: Scene, second: Int, walkthrough: Bool) -> NSBitmapImageRep {
        let vault = Vault(preview: true)
        vault.playful = false; vault.notchDuration = 1; vault.notchTransparency = 0.1
        AppRuntime.previewDate = Date(timeIntervalSince1970: 1_700_000_031 + Double(second))
        let content: AnyView
        let size: NSSize
        let title: String
        switch scene {
        case .accounts, .upcoming:
            size = NSSize(width: 410, height: 520)
            title = scene == .upcoming ? "The next code, before rollover" : "Your accounts, ready to fetch"
            content = AnyView(DenView(vault: vault, compact: false))
        case .popup:
            vault.accounts = Array(vault.displayed.prefix(1))
            size = NSSize(width: 300, height: 185); title = "A compact one-account popup"
            content = AnyView(QuickFetchView(vault: vault, notch: false, openDen: {}, close: {}))
        case .settings:
            size = NSSize(width: 410, height: 520); title = "Simple settings, in the same window"
            content = AnyView(SettingsView(vault: vault).background(ThemeBackground()))
        case .locked:
            vault.locked = true
            size = NSSize(width: 410, height: 520); title = "A locked den keeps codes hidden"
            content = AnyView(DenView(vault: vault, compact: false))
        }
        let stage = walkthrough ? NSSize(width: 410, height: 520) : size
        let canvas = NSRect(x: 0, y: 0, width: stage.width + 48, height: stage.height + 90)
        let root = VStack(spacing: 12) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer(minLength: 4)
                Text("DEMO").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(Palette.orange)
            }.frame(width: stage.width, height: 18)
            content.frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(width: stage.width, height: stage.height)
            Text("Sample accounts · No real credentials").font(.system(size: 9)).foregroundStyle(Palette.muted)
        }.padding(24).frame(width: canvas.width, height: canvas.height)
            .foregroundStyle(Palette.ink).background(Palette.background).preferredColorScheme(.light)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: canvas, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host; host.frame = canvas; host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: canvas) else { fatalError("Cannot capture documentation view") }
        host.cacheDisplay(in: canvas, to: bitmap)
        return bitmap
    }
}
