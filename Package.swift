// swift-tools-version: 5.9
import PackageDescription
import Foundation

let localNotchwork = ProcessInfo.processInfo.environment["NOTCHWORK_PACKAGE_PATH"]
let notchwork: Package.Dependency = localNotchwork.map { .package(name: "notchwork", path: $0) }
    ?? .package(url: "https://github.com/jesseglab/notchwork.git", exact: "0.1.1")
let package = Package(name: "Portkeeper", platforms: [.macOS(.v14)], products: [
    .executable(name: "Portkeeper", targets: ["Portkeeper"])
], dependencies: [notchwork], targets: [
    .executableTarget(name: "Portkeeper", dependencies: [.product(name: "NotchworkKit", package: "notchwork")],
        path: "Sources", exclude: ["Info.plist", "Portkeeper-setup.md", "runner.c"])
])
