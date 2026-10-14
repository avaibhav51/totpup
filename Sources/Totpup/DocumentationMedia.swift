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
        try exportNotchShowcase(to: directory)
        AppRuntime.previewDate = nil
        print("Exported screenshots, app walkthrough, and notch/transparency showcase to \(directory.path)")
    }

    private static func exportNotchShowcase(to directory: URL) throws {
        let compact = notchCapture(transparency: 0.1, reveal: 1)
        guard let png = compact.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent("notch-compact.png"))
        for percent in [0, 40, 70] {
            let shot = notchCapture(transparency: Double(percent) / 100, reveal: 1)
            guard let data = shot.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: directory.appendingPathComponent("notch-transparency-\(percent).png"))
        }
        guard let gif = CGImageDestinationCreateWithURL(directory.appendingPathComponent("notch-demo.gif") as CFURL, UTType.gif.identifier as CFString, 40, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<40 {
            let reveal: Double = frame < 4 ? 0 : (frame < 9 ? Double(frame - 4) / 5 : (frame < 34 ? 1 : max(0, 1 - Double(frame - 34) / 5)))
            let transparency = frame < 16 ? 0.1 : (frame < 25 ? 0.4 : 0.7)
            let bitmap = notchCapture(transparency: transparency, reveal: reveal)
            guard let cg = bitmap.cgImage else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(gif, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func notchCapture(transparency: Double, reveal: Double) -> NSBitmapImageRep {
        let vault = Vault(preview: true)
        vault.playful = false; vault.notchTransparency = transparency
        vault.accounts = Array(vault.displayed.prefix(1))
        AppRuntime.previewDate = Date(timeIntervalSince1970: 1_700_000_036)
        let root = VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A little peek from the notch.").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Hover to fetch. Let your pup tuck away.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text("DEMO").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Palette.orange)
            }
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.69, green: 0.79, blue: 0.70), Color(red: 0.95, green: 0.78, blue: 0.59)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.35)).frame(width: 320).offset(x: -190, y: 135)
                Circle().fill(Palette.orange.opacity(0.22)).frame(width: 260).offset(x: 180, y: 95)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(0..<11) { line in
                        Capsule().fill(Palette.ink.opacity(0.12)).frame(width: line % 3 == 0 ? 190 : 280, height: 6)
                    }
                }.frame(width: 310, alignment: .leading).padding(22)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 18)).offset(y: 100)
                Rectangle().fill(.white.opacity(0.3)).frame(height: 28)
                HStack {
                    Image(systemName: "apple.logo")
                    Text("Demo desktop").font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Image(systemName: "pawprint.fill")
                }.font(.system(size: 11)).padding(.horizontal, 16).frame(height: 28)
                QuickFetchView(vault: vault, notch: true, openDen: {}, close: {})
                    .frame(width: 300, height: 185).opacity(reveal)
                    .offset(y: 36 - (1 - reveal) * 200)
                UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                    .fill(Color.black).frame(width: 130, height: 28)
            }.frame(width: 560, height: 330).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18))
            HStack {
                Text("ONE ACCOUNT · 300 × 185").font(.system(size: 9, weight: .semibold, design: .monospaced))
                Spacer()
                Text("Background transparency: \(Int((transparency * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold))
            }
            Text("Illustrated desktop + actual notch view · Sample account · Codes stay opaque")
                .font(.system(size: 9)).foregroundStyle(Palette.muted)
        }.padding(24).frame(width: 608, height: 470)
            .foregroundStyle(Palette.ink).background(Palette.background).preferredColorScheme(.light)
        let rectangle = NSRect(x: 0, y: 0, width: 608, height: 470)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: rectangle, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host; host.frame = rectangle; host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: rectangle) else { fatalError("Cannot capture notch showcase") }
        host.cacheDisplay(in: rectangle, to: bitmap)
        return bitmap
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
