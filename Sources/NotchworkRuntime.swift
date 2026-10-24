import AppKit
import Foundation
import Darwin

/// The prerequisite is shipped inside Portkeeper, then installed once for all clients.
enum NotchworkRuntime {
    static let bundleID = "app.notchwork.host"
    static let apiVersion = 2
    static let minimumBuild = 8
    static func compatible(_ url: URL) -> Bool {
        guard let bundle = Bundle(url: url), bundle.bundleIdentifier == bundleID,
              let version = bundle.object(forInfoDictionaryKey: "NotchworkAPIVersion") as? Int,
              version >= apiVersion,
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              (Int(build) ?? 0) >= minimumBuild, let executable = bundle.executableURL else { return false }
        return FileManager.default.isExecutableFile(atPath: executable.path)
    }
    static func verifySignature(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RuntimeError.invalidBundle }
    }
    static func install(bundled: URL, candidates: [URL], destination: URL,
                        verify: (URL) throws -> Void = verifySignature) throws -> URL {
        let files = FileManager.default
        for candidate in candidates where compatible(candidate) {
            try verify(candidate)
            return candidate
        }
        guard compatible(bundled) else { throw RuntimeError.missingBundle }
        let folder = destination.deletingLastPathComponent()
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let stage = folder.appendingPathComponent(".Notchwork-install-\(UUID().uuidString).app")
        defer { try? files.removeItem(at: stage) }
        try files.copyItem(at: bundled, to: stage)
        // Cloud-backed source folders can attach Finder metadata after packaging.
        // Clean only the staged copy; preserve quarantine and all signed contents.
        let stagedItems = [stage] + (files.enumerator(at: stage, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
        for item in stagedItems {
            for attribute in ["com.apple.FinderInfo", "com.apple.ResourceFork"] {
                _ = item.path.withCString { path in attribute.withCString { removexattr(path, $0, XATTR_NOFOLLOW) } }
            }
        }
        guard compatible(stage) else { throw RuntimeError.invalidBundle }
        try verify(stage)
        if files.fileExists(atPath: destination.path) {
            // Never overwrite another installation or an unrelated file in place.
            if compatible(destination) { try verify(destination); return destination }
            throw RuntimeError.incompatibleInstallation(destination.path)
        }
        do { try files.moveItem(at: stage, to: destination) }
        catch {
            // Another client may have completed the same first-run install.
            guard compatible(destination) else { throw error }
            try verify(destination)
        }
        return destination
    }
    @MainActor static func ensureRunning() async throws {
        let userApp = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Notchwork.app")
        let systemApp = URL(fileURLWithPath: "/Applications/Notchwork.app")
        let bundled = Bundle.main.resourceURL!.appendingPathComponent("Notchwork/Notchwork.app")
        let target = try await Task.detached(priority: .utility) {
            try install(bundled: bundled, candidates: [userApp, systemApp], destination: userApp)
        }.value
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.contains(where: { $0.bundleURL.map(compatible) == true }) { return }
        guard running.isEmpty else { throw RuntimeError.olderRuntimeRunning }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try await NSWorkspace.shared.openApplication(at: target, configuration: configuration)
    }
    enum RuntimeError: LocalizedError {
        case missingBundle, invalidBundle, incompatibleInstallation(String), olderRuntimeRunning
        var errorDescription: String? {
            switch self {
            case .missingBundle: return "This Portkeeper build is missing its Notchwork prerequisite. Install the complete Portkeeper app."
            case .invalidBundle: return "Notchwork could not be verified. Reinstall the complete Portkeeper app."
            case .incompatibleInstallation(let path): return "An older Notchwork is installed at \(path). Move it aside and retry to install the bundled runtime."
            case .olderRuntimeRunning: return "Quit the older Notchwork app, then retry to start the bundled runtime."
            }
        }
    }
}
