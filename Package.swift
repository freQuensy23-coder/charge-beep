// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChargeBeep",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "charge-beep", targets: ["ChargeBeep"]),
        .executable(name: "ChargeBeepUI", targets: ["ChargeBeepUI"])
    ],
    targets: [
        .target(name: "ChargeBeepCore"),
        .target(name: "ChargeBeepSettings", dependencies: ["ChargeBeepCore"]),
        .executableTarget(name: "ChargeBeep", dependencies: ["ChargeBeepCore"]),
        .executableTarget(name: "ChargeBeepUI", dependencies: ["ChargeBeepSettings"]),
        .testTarget(name: "ChargeBeepCoreTests", dependencies: ["ChargeBeepCore"]),
        .executableTarget(name: "ChargeBeepUITestDriver",
                          dependencies: ["ChargeBeepCore", "ChargeBeepSettings"],
                          path: "Tests/UITestDriver")
    ]
)
