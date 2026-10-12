import AppKit
import LocalAuthentication
import Security
import SwiftUI
import TotpCore

struct Account: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var configuration: OTPConfiguration
    var isDemo = false
    var title: String { configuration.issuer.isEmpty ? configuration.label : configuration.issuer }
}

enum Keychain {
    static let service = "app.totpup.authenticator"
    static func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id, kSecAttrSynchronizable as String: false]
    }
    static func put(_ value: Data, id: String) throws {
        let result = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if result == errSecItemNotFound {
            var item = query(id)
            item[kSecValueData as String] = value
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw failure(status) }
        } else if result != errSecSuccess { throw failure(result) }
    }
    static func get(_ id: String) throws -> Data? {
        var item = query(id)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw failure(status) }
        return value as? Data
    }
    static func delete(_ id: String) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    static func failure(_ status: OSStatus) -> NSError {
        NSError(domain: "Totpup.Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey:
            "Keychain couldn’t complete this action. " + (SecCopyErrorMessageString(status, nil) as String? ?? "Try again.")])
    }
}

@MainActor
final class Vault: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var locked = false
    @Published var error: String?
    @Published var copiedID: UUID?
    @Published var showAdd = false
    @Published var showSettings = false
    @Published var menuBarEnabled: Bool {
        didSet { guard persistsPreferences else { return }; UserDefaults.standard.set(menuBarEnabled, forKey: "menuBarEnabled") }
    }
    @Published var notchEnabled: Bool {
        didSet { guard persistsPreferences else { return }; UserDefaults.standard.set(notchEnabled, forKey: "notchEnabled") }
    }
    @Published var notchDuration: Double {
        didSet { guard persistsPreferences else { return }; UserDefaults.standard.set(notchDuration <= 0.5 ? 0.5 : (notchDuration <= 1 ? 1.0 : 2.0), forKey: "notchDuration") }
    }
    @Published var popupEnabled: Bool {
        didSet { guard persistsPreferences else { return }; UserDefaults.standard.set(popupEnabled, forKey: "popupEnabled") }
    }
    @Published var requireUnlock: Bool {
        didSet { guard persistsPreferences else { return }; UserDefaults.standard.set(requireUnlock, forKey: "requireUnlock") }
    }
    @Published var playful: Bool {
        didSet { guard persistsPreferences else { return }; UserDefaults.standard.set(playful, forKey: "playful") }
    }
    private let persistsPreferences: Bool
    private var secrets: [UUID: String] = [:]
    private var clipboardGeneration = 0
    private var idleTask: Task<Void, Never>?
    private(set) var ready = false

    init(preview: Bool = false) {
        persistsPreferences = !preview
        let defaults = UserDefaults.standard
        menuBarEnabled = defaults.object(forKey: "menuBarEnabled") as? Bool ?? true
        notchEnabled = defaults.object(forKey: "notchEnabled") as? Bool ?? true
        let savedNotchDuration = (defaults.object(forKey: "notchDuration") as? NSNumber)?.doubleValue ?? 1
        notchDuration = savedNotchDuration <= 0.5 ? 0.5 : (savedNotchDuration <= 1 ? 1 : 2)
        popupEnabled = defaults.object(forKey: "popupEnabled") as? Bool ?? true
        requireUnlock = defaults.bool(forKey: "requireUnlock")
        playful = defaults.object(forKey: "playful") as? Bool ?? true
        if preview { requireUnlock = false; locked = false; ready = true; return }
        locked = requireUnlock
        if !locked { load() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        }
    }
    var displayed: [Account] {
        if accounts.isEmpty && ready {
            return [Account(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, configuration: .init(issuer: "JumpCloud", label: "hello@totpup.demo"), isDemo: true),
                    Account(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, configuration: .init(issuer: "GitHub", label: "your next adventure"), isDemo: true)]
        }
        return accounts
    }
    func load() {
        do {
            let data = try Keychain.get("accounts")
            let loaded = try data.map { try JSONDecoder().decode([Account].self, from: $0) } ?? []
            var loadedSecrets: [UUID: String] = [:]
            for account in loaded {
                guard let value = try Keychain.get(account.id.uuidString), let secret = String(data: value, encoding: .utf8) else {
                    throw NSError(domain: "Totpup", code: 1, userInfo: [NSLocalizedDescriptionKey: "A saved account is missing its secret. Restore it from its enrollment setup."])
                }
                loadedSecrets[account.id] = secret
            }
            accounts = loaded; secrets = loadedSecrets; ready = true
            touch()
        } catch { self.error = error.localizedDescription; ready = false }
    }
    func add(_ enrollment: Enrollment) throws {
        guard !locked, ready else { throw NSError(domain: "Totpup", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unlock the vault before adding an account."]) }
        let account = Account(configuration: enrollment.configuration)
        try Keychain.put(Data(enrollment.secret.utf8), id: account.id.uuidString)
        do { try Keychain.put(JSONEncoder().encode(accounts + [account]), id: "accounts") }
        catch { try? Keychain.delete(account.id.uuidString); throw error }
        accounts.append(account); secrets[account.id] = enrollment.secret; touch()
    }
    func remove(_ account: Account) {
        guard !locked else { return }
        do {
            let updated = accounts.filter { $0.id != account.id }
            let previous = try JSONEncoder().encode(accounts)
            try Keychain.put(JSONEncoder().encode(updated), id: "accounts")
            do { try Keychain.delete(account.id.uuidString) }
            catch { try? Keychain.put(previous, id: "accounts"); throw error }
            secrets.removeValue(forKey: account.id)
            accounts = updated
        } catch { self.error = error.localizedDescription }
    }
    func code(_ account: Account, at date: Date) -> String? {
        guard !locked else { return nil }
        let secret = account.isDemo ? "JBSWY3DPEHPK3PXP" : secrets[account.id]
        guard let secret else { return nil }
        return try? TOTP.code(secret: secret, configuration: account.configuration, at: date)
    }
    func upcomingCode(_ account: Account, at date: Date) -> String? {
        guard account.configuration.remaining(at: date) < 5 else { return nil }
        let period = Double(account.configuration.period)
        let boundary = Date(timeIntervalSince1970: (floor(date.timeIntervalSince1970 / period) + 1) * period)
        return code(account, at: boundary)
    }
    func copy(_ account: Account) {
        guard let code = code(account, at: Date()) else {
            error = locked ? "Unlock your vault before copying a code." : "This code is unavailable. Reopen the account and try again."
            return
        }
        touch()
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(code, forType: .string) else {
            error = "The code couldn’t be copied to the clipboard. Try again."
            return
        }
        let changeCount = NSPasteboard.general.changeCount
        copiedID = account.id
        clipboardGeneration += 1
        let generation = clipboardGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.clipboardGeneration == generation { self?.copiedID = nil }
            try? await Task.sleep(for: .seconds(18))
            if NSPasteboard.general.changeCount == changeCount { NSPasteboard.general.clearContents() }
        }
    }
    func touch() {
        idleTask?.cancel()
        guard requireUnlock, !locked else { return }
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(120)); self?.lock() } catch {}
        }
    }
    func lock() {
        idleTask?.cancel(); secrets.removeAll(); accounts.removeAll(); ready = false; locked = true
        showAdd = false
    }
    func unlock() async {
        let context = LAContext()
        do {
            let accepted = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Reveal your Totpup verification codes")
            if accepted { locked = false; load() }
        } catch { self.error = error.localizedDescription }
    }
}
