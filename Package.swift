// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Coordinated source distribution: both repositories are supplied side by side.
let localNotchwork = ProcessInfo.processInfo.environment["NOTCHWORK_PACKAGE_PATH"] ?? "../notchwork"
let notchwork = Package.Dependency.package(name: "notchwork", path: localNotchwork)
let package = Package(name: "Portkeeper", platforms: [.macOS(.v14)], products: [
    .executable(name: "Portkeeper", targets: ["Portkeeper"])
], dependencies: [notchwork], targets: [
    .executableTarget(name: "Portkeeper", dependencies: [.product(name: "NotchworkKit", package: "notchwork")],
        path: "Sources", exclude: ["Info.plist", "Portkeeper-setup.md", "runner.c"])
])
