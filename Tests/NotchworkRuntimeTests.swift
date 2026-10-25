import Foundation

extension TerminalWorkspaceTests {
    @MainActor static func runRuntimeTests() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("runtime-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("Bundled.app"), installed = root.appendingPathComponent("Applications/Notchwork.app")
        do {
            let executable = bundled.appendingPathComponent("Contents/MacOS/Notchwork")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            let plist: [String: Any] = ["CFBundleIdentifier": NotchworkRuntime.bundleID, "CFBundleExecutable": "Notchwork", "CFBundlePackageType": "APPL", "NotchworkAPIVersion": 2, "CFBundleVersion": String(NotchworkRuntime.minimumBuild)]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: bundled.appendingPathComponent("Contents/Info.plist"))
            let older = root.appendingPathComponent("Older.app")
            try FileManager.default.copyItem(at: bundled, to: older)
            var oldPlist = plist; oldPlist["CFBundleVersion"] = "9"
            try PropertyListSerialization.data(fromPropertyList: oldPlist, format: .xml, options: 0).write(to: older.appendingPathComponent("Contents/Info.plist"))
            expect(!NotchworkRuntime.compatible(older), "The old runtime without side-hover is not reused")
            var verifications = 0
            let result = try NotchworkRuntime.install(bundled: bundled, candidates: [older], destination: installed, verify: { _ in verifications += 1 })
            expect(result == installed && NotchworkRuntime.compatible(installed), "Missing prerequisite is installed in the requested applications folder")
            expect(verifications == 1, "Staged bundle signature is verified before installation")
            let marker = installed.appendingPathComponent("keep.txt")
            try Data("existing".utf8).write(to: marker)
            let reused = try NotchworkRuntime.install(bundled: root.appendingPathComponent("missing"), candidates: [installed], destination: installed, verify: { _ in })
            expect(reused == installed && FileManager.default.fileExists(atPath: marker.path), "Existing compatible Notchwork is reused without reinstalling")
            let rejected = root.appendingPathComponent("Rejected/Notchwork.app")
            do {
                _ = try NotchworkRuntime.install(bundled: bundled, candidates: [], destination: rejected, verify: { _ in throw NSError(domain: "test", code: 1) })
                expect(false, "Reject invalid signature")
            } catch { expect(!FileManager.default.fileExists(atPath: rejected.path), "Signature failure leaves no installed runtime") }
            let occupied = root.appendingPathComponent("Unrelated.app")
            try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
            do {
                _ = try NotchworkRuntime.install(bundled: bundled, candidates: [], destination: occupied, verify: { _ in })
                expect(false, "Do not overwrite incompatible installation")
            } catch { expect(FileManager.default.fileExists(atPath: occupied.path), "Incompatible destination is preserved for manual recovery") }
            let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
            expect(!remaining.contains(where: { $0.hasPrefix(".Notchwork-install-") }), "Failed install cleans up its staged bundle")
        } catch { expect(false, "Runtime installer: \(error)") }
        print("All Notchwork prerequisite tests passed.")
    }
}
