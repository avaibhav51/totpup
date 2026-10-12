import AppKit
import SwiftUI
import TotpCore
import Vision
import UniformTypeIdentifiers

struct DenView: View {
    @ObservedObject var vault: Vault
    var compact: Bool
    @ViewState<String> private var query = ""
    @ViewState<Account?> private var deleting: Account?
    @FocusState private var searchFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var filtered: [Account] {
        vault.displayed.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.configuration.label.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        Group {
            if vault.showSettings { SettingsView(vault: vault) }
            else { denContent }
        }.background(ThemeBackground())
    }
    private var denContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "pawprint.fill").foregroundStyle(Palette.orange)
                    Text("totpup").font(.system(size: 25, weight: .heavy, design: .rounded)).tracking(-1)
                }
                Spacer()
                if !vault.locked {
                    iconButton("lock", help: "Lock your vault") { vault.lock() }
                }
                iconButton("slider.horizontal.3", help: "Settings") { vault.showSettings = true }
            }
            .padding(.horizontal, 18).padding(.top, 16)

            HStack(spacing: 12) {
                PupView(awake: !vault.locked, celebrate: vault.copiedID != nil, animate: vault.playful && !reduceMotion)
                    .frame(width: 65, height: 72).scaleEffect(0.55)
                    .accessibilityLabel(vault.locked ? "Sleeping pup" : "Your pup companion")
                VStack(alignment: .leading, spacing: 4) {
                    Text(vault.locked ? "Your pup is taking a nap." : "Your next code, ready to fetch.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(vault.locked ? "Unlock to see your accounts." : "Your little authentication companion.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 18).padding(.vertical, 8)

            if vault.locked {
                Spacer()
                Image(systemName: "touchid").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Palette.orange)
                Text("Your den is locked").font(.system(size: 20, weight: .semibold, design: .rounded)).padding(.top, 14)
                Text("Use Touch ID or your Mac login password.").font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.top, 4)
                Button { Task { await vault.unlock() } } label: {
                    Label("Wake up & unlock", systemImage: "pawprint.fill").frame(maxWidth: .infinity)
                }.buttonStyle(PupButtonStyle()).padding(.horizontal, 40).padding(.top, 20)
                Spacer()
            } else {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Find an account", text: $query).textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                    Text("⌘ F").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                }
                .padding(12).background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.ink.opacity(0.07)))
                .padding(.horizontal, 18)

                HStack {
                    Text(vault.accounts.isEmpty ? "A PEEK INSIDE" : "YOUR ACCOUNTS").tracking(1.7)
                    Spacer()
                    Text(vault.accounts.isEmpty ? "DEMO" : "\(vault.accounts.count) IN YOUR DEN")
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Palette.sage.opacity(0.6), in: Capsule())
                }.font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Palette.muted)
                    .padding(.horizontal, 19).padding(.top, 12).padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { account in
                            AccountCard(account: account, vault: vault, animated: vault.playful && !reduceMotion)
                                .contextMenu {
                                    if !account.isDemo {
                                        Button("Copy code") { vault.copy(account) }
                                        Button("Remove account", role: .destructive) { deleting = account }
                                    }
                                }
                        }
                        if filtered.isEmpty {
                            Text(query.isEmpty ? "Add an account to get started." : "No pups by that name.")
                                .font(.system(size: 13)).foregroundStyle(Palette.muted).padding(25)
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 12)
                }.scrollIndicators(.hidden)

                Button { vault.showAdd = true } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Bring an account home")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(PupButtonStyle()).disabled(!vault.ready).padding(.horizontal, 18).padding(.top, 6)
            }

            HStack {
                Label("LOCAL. LOVABLE. YOURS.", systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1)
                Spacer()
                if compact { Button("Open den ↗") { openWindow(id: "den"); NSApp.activate(ignoringOtherApps: true) }.buttonStyle(.plain).font(.system(size: 10)) }
                else { Text("woof.").font(.system(size: 11, design: .rounded)).italic() }
            }.foregroundStyle(Palette.muted).padding(.horizontal, 19).padding(.vertical, 12)
        }
        .foregroundStyle(Palette.ink)
        .background(Button("") { searchFocused = true }.keyboardShortcut("f").hidden().accessibilityHidden(true))
        .preferredColorScheme(.light)
        .onAppear {
            if !compact && !AppRuntime.isPreview { AppRuntime.openDen = { openWindow(id: "den") } }
        }
        .sheet(isPresented: $vault.showAdd) { EnrollmentView(vault: vault) }
        .alert("A little snag", isPresented: Binding(get: { vault.error != nil }, set: { if !$0 { vault.error = nil } })) {
            Button("Okay") { vault.error = nil }
        } message: { Text(vault.error ?? "") }
        .confirmationDialog("Remove \(deleting?.title ?? "account")? You’ll need its setup secret to add it again.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Remove account", role: .destructive) { if let deleting { vault.remove(deleting) }; deleting = nil }
        }
    }
    func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 13)).frame(width: 30, height: 30).background(Palette.ink.opacity(0.05), in: Circle()) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

struct AccountCard: View {
    var account: Account
    @ObservedObject var vault: Vault
    var animated: Bool
    @ViewState<Bool> private var hovering = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = account.configuration.remaining(at: timeline.date)
            let code = vault.code(account, at: timeline.date) ?? String(repeating: "—", count: account.configuration.digits)
            let split = code.index(code.startIndex, offsetBy: code.count / 2)
            Button { vault.copy(account) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(String(account.title.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink)
                            .frame(width: 34, height: 34).background(Palette.sage, in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.title).font(.system(size: 13, weight: .semibold))
                            Text(account.configuration.label).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: vault.copiedID == account.id ? "checkmark" : (account.isDemo ? "sparkles" : "doc.on.doc"))
                            .contentTransition(.symbolEffect(.replace)).font(.system(size: 12))
                            .foregroundStyle(vault.copiedID == account.id ? Color.green : Palette.muted)
                    }
                    HStack {
                        Text("\(code[..<split]) \(code[split...])")
                            .font(.system(size: 30, weight: .semibold, design: .monospaced)).tracking(2)
                            .contentTransition(.numericText())
                            .animation(animated ? .easeOut(duration: 0.25) : nil, value: code)
                        Spacer(minLength: 4)
                        ZStack {
                            Circle().stroke(Palette.ink.opacity(0.08), lineWidth: 3)
                            Circle().trim(from: 0, to: Double(remaining) / Double(account.configuration.period))
                                .stroke(remaining <= 5 ? Palette.orange : Palette.ink.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(animated && remaining != account.configuration.period ? .easeOut(duration: 0.18) : nil, value: remaining)
                            Text("\(remaining)").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }.frame(width: 32, height: 32)
                    }
                    UpcomingCodeView(account: account, vault: vault, date: timeline.date, animated: animated)
                    if vault.copiedID == account.id {
                        Text("Fetched! Clipboard clears in 20 seconds.").font(.system(size: 9)).foregroundStyle(Palette.muted)
                    }
                }
                .padding(13).background(.white.opacity(hovering ? 1 : 0.8), in: RoundedRectangle(cornerRadius: 19))
                .overlay(RoundedRectangle(cornerRadius: 19).stroke(hovering ? Palette.orange.opacity(0.35) : Palette.ink.opacity(0.06)))
                .shadow(color: Palette.ink.opacity(hovering ? 0.07 : 0.02), radius: hovering ? 12 : 3, y: 4)
                .scaleEffect(hovering && animated ? 1.012 : 1)
            }
            .buttonStyle(.plain).onHover { value in withAnimation(animated ? .easeOut(duration: 0.2) : nil) { hovering = value } }
            .help(account.isDemo ? "Copy demo code — not a real account" : "Copy this code")
            .accessibilityLabel("\(account.title), \(account.isDemo ? "demo" : "verification code"), \(remaining) seconds remaining")
        }
    }
}

struct UpcomingCodeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let account: Account
    @ObservedObject var vault: Vault
    let date: Date
    let animated: Bool
    var body: some View {
        let next = vault.upcomingCode(account, at: date)
        Text(next.map { code in
            let split = code.index(code.startIndex, offsetBy: code.count / 2)
            return "Next · \(code[..<split]) \(code[split...])"
        } ?? "Next · ••• •••")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.muted).frame(height: 12, alignment: .leading)
            .opacity(next == nil ? 0 : 1)
            .animation(animated && !reduceMotion ? .easeInOut(duration: 0.25) : nil, value: next)
            .help("This code becomes valid when the current code expires.")
            .accessibilityHidden(next == nil)
    }
}

struct PupButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 14).foregroundStyle(.white)
            .background(Palette.ink.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 13))
    }
}

struct EnrollmentView: View {
    @ObservedObject var vault: Vault
    @Environment(\.dismiss) private var dismiss
    @ViewState<String> private var secret = ""
    @ViewState<String> private var issuer = ""
    @ViewState<String> private var label = ""
    @ViewState<String?> private var error: String?
    @ViewState<Bool> private var scanning = false
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Image(systemName: "pawprint.fill").foregroundStyle(Palette.orange); Text("A new friend for your den").font(.system(size: 23, weight: .bold, design: .rounded)); Spacer() }
            Text("Use the TOTP setup secret or QR from your account’s security settings. Organization accounts must allow third-party authenticators.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 6) {
                Text("SETUP SECRET OR OTPAUTH LINK").font(.system(size: 9, weight: .bold, design: .monospaced))
                SecureField("Paste your setup secret", text: $secret).textFieldStyle(.roundedBorder)
            }
            HStack {
                Button { importQR() } label: { Label(scanning ? "Reading QR…" : "Import QR image", systemImage: "qrcode") }.disabled(scanning)
                Text("PNG, JPEG, or a screenshot file").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            TextField("Service name, e.g. JumpCloud", text: $issuer).textFieldStyle(.roundedBorder)
            TextField("Account name or email", text: $label).textFieldStyle(.roundedBorder)
            Text("Secrets stay in this Mac’s Keychain. Totpup doesn’t upload them.").font(.system(size: 11)).foregroundStyle(Palette.muted)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(Palette.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { secret = ""; dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Welcome home") { save() }.buttonStyle(PupButtonStyle()).disabled(secret.isEmpty || vault.locked || scanning)
            }.padding(.top, 10)
        }.padding(28).frame(width: 470).background(Palette.background).foregroundStyle(Palette.ink).preferredColorScheme(.light)
    }
    func save() {
        do {
            var enrollment = try Enrollment.parse(secret, issuer: issuer.trimmingCharacters(in: .whitespacesAndNewlines), label: label.trimmingCharacters(in: .whitespacesAndNewlines))
            if !issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { enrollment.configuration.issuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { enrollment.configuration.label = label.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !enrollment.configuration.issuer.isEmpty || !enrollment.configuration.label.isEmpty else { error = "Give this account a service name or account name."; return }
            try vault.add(enrollment); secret = ""; dismiss()
        } catch { self.error = error.localizedDescription }
    }
    func importQR() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scanning = true
        Task {
            do {
                let value = try await Task.detached {
                    let request = VNDetectBarcodesRequest()
                    request.symbologies = [.qr]
                    try VNImageRequestHandler(url: url).perform([request])
                    let values = (request.results ?? []).compactMap(\.payloadStringValue)
                    guard values.count == 1, let value = values.first else {
                        throw NSError(domain: "Totpup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose an image containing exactly one TOTP enrollment QR."])
                    }
                    return value
                }.value
                let enrollment = try Enrollment.parse(value)
                // A QR must be a TOTP URI; don't mistake a Protect activation token for a raw secret.
                guard value.lowercased().hasPrefix("otpauth://totp/") else { throw OTPError.unsupportedType }
                secret = value; issuer = enrollment.configuration.issuer; label = enrollment.configuration.label; error = nil
            } catch { self.error = error.localizedDescription }
            scanning = false
        }
    }
}

struct SettingsView: View {
    @ObservedObject var vault: Vault
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { vault.showSettings = false } label: {
                    Image(systemName: "chevron.left").frame(width: 28, height: 28)
                }.buttonStyle(.plain).help("Back to accounts").keyboardShortcut(.cancelAction)
                Text("Settings").font(.system(size: 21, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: "pawprint.fill").foregroundStyle(Palette.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("QUICK ACCESS")
                    detail("Menu bar paw", help: "Click the paw to fetch a code; right-click for Open and Quit. The Dock icon appears while a window or popup is visible.") {
                        Toggle("", isOn: $vault.menuBarEnabled).labelsHidden()
                    }
                    detail("Notch hover", help: "Hover below the notch to reveal the panel. It stays open while you interact with it.") {
                        Toggle("", isOn: $vault.notchEnabled).labelsHidden()
                    }
                    if vault.notchEnabled {
                        HStack {
                            Text("Notch visibility").font(.system(size: 12))
                            Spacer()
                            Picker("Notch visibility", selection: $vault.notchDuration) {
                                Text("0.5s").tag(0.5)
                                Text("1s").tag(1.0)
                                Text("2s").tag(2.0)
                            }.pickerStyle(.segmented).labelsHidden().frame(width: 154)
                        }
                    }
                    detail("Quick popup", help: "Control + Option + P. Drag the header to move it; its position is remembered. Click outside or press Escape to dismiss.") {
                        Toggle("", isOn: $vault.popupEnabled).labelsHidden()
                    }
                    Divider()
                    section("APPEARANCE")
                    detail("Playful motion", help: "Brief pup animations and code transitions. System Reduce Motion is respected.") {
                        Toggle("", isOn: $vault.playful).labelsHidden()
                    }
                    Divider()
                    section("PROTECTION")
                    detail("Touch ID or Mac password", help: "Locks after two minutes without an account action, on sleep, and at launch. Unlock before disabling protection.") {
                        Toggle("", isOn: $vault.requireUnlock).labelsHidden()
                            .onChange(of: vault.requireUnlock) { oldValue, newValue in
                                if newValue { vault.lock() }
                                else if oldValue && vault.locked { vault.requireUnlock = true }
                                else { vault.touch() }
                            }
                    }
                    Divider()
                    section("ON THE HORIZON")
                    Text("Browser autofill · CLI · Custom widgets · Windows support")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack {
                        Text("Made by").foregroundStyle(Palette.muted)
                        Link("Vaibhav Agarwal", destination: URL(string: "https://avaibhav51.github.io/")!).help("Visit Vaibhav’s portfolio")
                        Spacer()
                        Link("GitHub", destination: URL(string: "https://github.com/avaibhav51")!)
                    }.font(.system(size: 11))
                }.padding(.trailing, 6)
            }.scrollIndicators(.hidden)
        }.padding(18).foregroundStyle(Palette.ink).preferredColorScheme(.light)
    }
    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
    }
    private func detail<Content: View>(_ title: String, help: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(Palette.muted)
                .help(help).accessibilityLabel(help)
            Spacer()
            content()
        }.help(help)
    }
}
