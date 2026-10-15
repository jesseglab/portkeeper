import Foundation

extension TerminalWorkspaceTests {
    @MainActor static func runNotchworkBridgeTests() async {
        let model = makeModel()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portkeeper-bridge-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = NotchworkBridge(model: model, directory: directory, connectionFile: nil)
        defer { bridge.stop() }
        let file = directory.appendingPathComponent("notchwork.json")
        let service = config("Worker", "Live bridge", "sleep 10")
        model.configs = [service]
        model.logs[service.id] = "SECRET_TOKEN=should-not-leave-portkeeper"
        expect(!FileManager.default.fileExists(atPath: file.path), "Notchwork sharing is off by default")
        expect(!NotchworkBridge.perform("service.start", value: service.id.uuidString, model: model), "Host callbacks cannot act while sharing is off")
        model.shareWithNotchwork = true
        expect(!NotchworkBridge.perform("run-shell", value: "echo unsafe", model: model), "Unknown custom actions cannot execute commands")
        expect(!NotchworkBridge.perform("service.start", value: UUID().uuidString, model: model), "Custom actions reject unknown service identities")
        expect(NotchworkBridge.perform("service.start", value: service.id.uuidString, model: model), "Custom UI callback starts a real managed service")
        for _ in 0..<50 {
            if case .running = model.state(for: service) { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        bridge.update(force: true)
        try? await Task.sleep(nanoseconds: 200_000_000)
        let data = try! Data(contentsOf: file)
        let snapshot = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let card = snapshot["activity"] as! [String: Any]
        expect(card["sourceID"] as? String == "app.portkeeper", "Bridge publishes the real Portkeeper source")
        expect((card["details"] as? [String])?.first?.contains("Running") == true, "Bridge reflects a running managed service")
        expect(card["interface"] != nil, "Bridge carries Portkeeper’s own interface")
        let custom = PortkeeperNotchworkUI.interface(model)
        expect((try? custom.validate()) != nil, "Portkeeper interface fits the shared host limits")
        expect(PortkeeperNotchworkUI.escape("<script>\"&") == "&lt;script&gt;&quot;&amp;", "Project and service labels cannot inject HTML")
        let text = String(data: data, encoding: .utf8)!
        expect(!text.contains("SECRET_TOKEN") && !text.contains("sleep 10"), "Bridge excludes logs and commands")
        model.errors[service.id] = "SECRET_TOKEN=private diagnostic"
        bridge.update(force: true)
        try? await Task.sleep(nanoseconds: 200_000_000)
        let failure = String(data: try! Data(contentsOf: file), encoding: .utf8)!
        expect(failure.contains("urgent") && !failure.contains("private diagnostic"), "Service failure becomes priority without diagnostic contents")
        expect(NotchworkBridge.perform("service.stop", value: service.id.uuidString, model: model), "Custom UI callback stops its managed service")
        model.shareWithNotchwork = false
        bridge.update()
        try? await Task.sleep(nanoseconds: 200_000_000)
        expect(!FileManager.default.fileExists(atPath: file.path), "Disconnect removes the bridge snapshot")
    }
}
