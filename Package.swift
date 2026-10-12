// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Totpup",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Totpup", targets: ["Totpup"]), .executable(name: "OTPVerify", targets: ["OTPVerify"])],
    targets: [
        .target(name: "TotpCore"),
        .executableTarget(name: "Totpup", dependencies: ["TotpCore"]),
        .executableTarget(name: "OTPVerify", dependencies: ["TotpCore"], path: "Tests/TotpCoreTests")
    ]
)
