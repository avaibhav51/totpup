import Foundation
import TotpCore

// Dependency-free RFC verification so Command Line Tools users don't need XCTest.
var checks = 0
@MainActor func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    guard actual == expected else { fatalError("FAILED: \(label)") }
    checks += 1
}
@MainActor func rejects(_ label: String, _ operation: () throws -> Void) {
    do { try operation() } catch { checks += 1; return }
    fatalError("FAILED: accepted \(label)")
}
let sha1 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
let sha256 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA"
let sha512 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA"
let times: [Double] = [59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000]
let vectors: [(OTPAlgorithm, String, [String])] = [
    (.sha1, sha1, ["94287082", "07081804", "14050471", "89005924", "69279037", "65353130"]),
    (.sha256, sha256, ["46119246", "68084774", "67062674", "91819424", "90698825", "77737706"]),
    (.sha512, sha512, ["90693936", "25091201", "99943326", "93441116", "38618901", "47863826"])
]
for (algorithm, secret, expected) in vectors {
    for (index, time) in times.enumerated() {
        equal(try TOTP.code(secret: secret, configuration: .init(issuer: "RFC", label: "test", algorithm: algorithm, digits: 8), at: Date(timeIntervalSince1970: time)), expected[index], "RFC \(algorithm) at \(time)")
    }
}
let enrollment = try Enrollment.parse("otpauth://totp/JumpCloud:hello%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=JumpCloud&period=30")
equal(enrollment.configuration.issuer, "JumpCloud", "issuer")
equal(enrollment.configuration.label, "hello@example.com", "decoded label")
equal(enrollment.configuration.remaining(at: Date(timeIntervalSince1970: 59)), 1, "last second")
equal(enrollment.configuration.remaining(at: Date(timeIntervalSince1970: 60)), 30, "new period")
equal(try TOTP.code(secret: enrollment.secret, configuration: enrollment.configuration, at: Date(timeIntervalSince1970: 59)) != TOTP.code(secret: enrollment.secret, configuration: enrollment.configuration, at: Date(timeIntervalSince1970: 60)), true, "rollover")
for uri in ["otpauth://hotp/test?secret=JBSWY3DPEHPK3PXP", "otpauth://totp/test?secret=JBSWY3DPEHPK3PXP&period=0", "otpauth://totp/test?secret=JBSWY3DPEHPK3PXP&algorithm=MD5", "otpauth://totp/test?secret=JBSWY3DPEHPK3PXP&digits=nope"] {
    rejects("invalid enrollment") { _ = try Enrollment.parse(uri) }
}
for secret in ["ABC!", "A", "MY=A"] { rejects("invalid Base32") { _ = try TOTP.decodeBase32(secret) } }
print("Passed \(checks) checks: all 18 RFC 6238 vectors, enrollment parsing, countdown rollover, and invalid input rejection.")
