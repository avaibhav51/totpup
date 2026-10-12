import Foundation
import CryptoKit

public enum OTPAlgorithm: String, Codable, CaseIterable, Sendable {
    case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512"
}

public enum OTPError: LocalizedError {
    case invalidSecret, invalidURI, unsupportedType, invalidParameters
    public var errorDescription: String? {
        switch self {
        case .invalidSecret: "Enter a valid Base32 setup secret (letters A–Z and numbers 2–7)."
        case .invalidURI: "This isn’t a valid TOTP setup link. Use an otpauth://totp link or the setup secret."
        case .unsupportedType: "This code isn’t a standard TOTP setup. Push enrollment and HOTP aren’t supported yet."
        case .invalidParameters: "This account has unsupported code settings. Use 6–8 digits and a period of 1–300 seconds."
        }
    }
}

public struct OTPConfiguration: Codable, Equatable, Sendable {
    public var issuer: String
    public var label: String
    public var algorithm: OTPAlgorithm
    public var digits: Int
    public var period: Int

    public init(issuer: String, label: String, algorithm: OTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30) {
        self.issuer = issuer; self.label = label; self.algorithm = algorithm; self.digits = digits; self.period = period
    }
    public func validate() throws {
        guard (6...8).contains(digits), (1...300).contains(period) else { throw OTPError.invalidParameters }
    }
    public func remaining(at date: Date) -> Int {
        period - Int(floor(date.timeIntervalSince1970)).quotientAndRemainder(dividingBy: period).remainder
    }
}

public struct Enrollment: Sendable {
    public var configuration: OTPConfiguration
    public var secret: String

    public static func parse(_ input: String, issuer: String = "", label: String = "") throws -> Enrollment {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("otpauth:") else {
            _ = try TOTP.decodeBase32(trimmed)
            return Enrollment(configuration: OTPConfiguration(issuer: issuer, label: label), secret: trimmed)
        }
        guard let url = URLComponents(string: trimmed), url.scheme?.lowercased() == "otpauth" else { throw OTPError.invalidURI }
        guard url.host?.lowercased() == "totp" else { throw OTPError.unsupportedType }
        let items = url.queryItems ?? []
        func value(_ key: String) -> String? { items.first { $0.name.lowercased() == key }?.value }
        guard let secret = value("secret") else { throw OTPError.invalidSecret }
        _ = try TOTP.decodeBase32(secret)
        let path = String(url.path.dropFirst())
        let parts = path.split(separator: ":", maxSplits: 1).map(String.init)
        let parsedIssuer = value("issuer") ?? (parts.count == 2 ? parts[0] : issuer)
        let parsedLabel = parts.count == 2 ? parts[1] : path
        let algorithm: OTPAlgorithm
        if let text = value("algorithm") {
            guard let supported = OTPAlgorithm(rawValue: text.uppercased()) else { throw OTPError.invalidParameters }
            algorithm = supported
        } else { algorithm = .sha1 }
        let digits: Int
        if let text = value("digits") { guard let number = Int(text) else { throw OTPError.invalidParameters }; digits = number }
        else { digits = 6 }
        let period: Int
        if let text = value("period") { guard let number = Int(text) else { throw OTPError.invalidParameters }; period = number }
        else { period = 30 }
        let configuration = OTPConfiguration(issuer: parsedIssuer, label: parsedLabel, algorithm: algorithm, digits: digits, period: period)
        try configuration.validate()
        return Enrollment(configuration: configuration, secret: secret)
    }
}

public enum TOTP {
    public static func decodeBase32(_ input: String) throws -> Data {
        let clean = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        let unpadded = clean.prefix { $0 != "=" }
        guard clean.dropFirst(unpadded.count).allSatisfy({ $0 == "=" }), !unpadded.isEmpty else { throw OTPError.invalidSecret }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var accumulator: UInt32 = 0
        var bits = 0
        var result = Data()
        for character in unpadded {
            guard let index = alphabet.firstIndex(of: character) else { throw OTPError.invalidSecret }
            accumulator = ((accumulator << 5) | UInt32(index)) & 0xffff
            bits += 5
            if bits >= 8 { bits -= 8; result.append(UInt8((accumulator >> bits) & 255)) }
        }
        guard !result.isEmpty, [0, 2, 4, 5, 7].contains(unpadded.count % 8),
              bits == 0 || (accumulator & ((1 << bits) - 1)) == 0 else { throw OTPError.invalidSecret }
        return result
    }

    public static func code(secret: String, configuration: OTPConfiguration, at date: Date = Date()) throws -> String {
        try configuration.validate()
        guard date.timeIntervalSince1970 >= 0 else { throw OTPError.invalidParameters }
        let key = SymmetricKey(data: try decodeBase32(secret))
        var counter = UInt64(floor(date.timeIntervalSince1970 / Double(configuration.period))).bigEndian
        let message = withUnsafeBytes(of: &counter) { Data($0) }
        let digest: [UInt8]
        switch configuration.algorithm {
        case .sha1: digest = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: digest = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: digest = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        let offset = Int(digest.last! & 15)
        let value = (UInt32(digest[offset] & 127) << 24) | (UInt32(digest[offset + 1]) << 16)
            | (UInt32(digest[offset + 2]) << 8) | UInt32(digest[offset + 3])
        let modulus = UInt32(pow(10, Double(configuration.digits)))
        return String(format: "%0*u", configuration.digits, value % modulus)
    }
}
