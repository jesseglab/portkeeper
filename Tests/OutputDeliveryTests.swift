import Foundation

extension TerminalWorkspaceTests {
    @MainActor static func runOutputDeliveryTests() async {
        let delivery = OutputDelivery()
        expect(delivery.append(Data("first\n".utf8)), "First output chunk schedules delivery")
        expect(!delivery.append(Data("second\n".utf8)), "Output bursts share one pending UI delivery")
        expect(delivery.drain().text == "first\nsecond\n", "Batched output preserves ordering")
        let utf8 = Array("🟢".utf8)
        _ = delivery.append(Data(utf8.prefix(2)))
        expect(delivery.drain().text.isEmpty, "Partial Unicode waits for the remaining bytes")
        _ = delivery.append(Data(utf8.suffix(2)))
        expect(delivery.drain().text == "🟢", "Unicode survives split pipe reads")
        let marker = Array("\u{1E}PORTKEEPER_INPUT_READY\u{1F}\n".utf8)
        _ = delivery.append(Data(marker.prefix(9)))
        expect(delivery.drain().text.isEmpty, "Partial readiness marker stays out of output")
        _ = delivery.append(Data(marker.dropFirst(9)) + Data("ready\n".utf8))
        let ready = delivery.drain()
        expect(ready.ready && ready.text == "ready\n", "Readiness survives split deliveries")
        _ = delivery.append(Data(marker) + Data(repeating: 65, count: 1_000_000))
        let bounded = delivery.drain()
        expect(bounded.ready && bounded.text.utf8.count <= OutputDelivery.capacity, "Flood intake is bounded without losing readiness")
        _ = delivery.append(Data("last line".utf8))
        expect(delivery.drain(final: true).text == "last line", "Final output flushes without waiting for another chunk")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("portkeeper-persistence-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("service.log")
        let writer = LogPersistence()
        writer.save(Data("old".utf8), to: url); writer.save(Data("latest".utf8), to: url)
        writer.flush()
        expect((try? String(contentsOf: url)) == "latest", "Coalesced persistence saves the newest snapshot")
        writer.save(Data("pending".utf8), to: url); writer.remove(url); writer.flush()
        expect(!FileManager.default.fileExists(atPath: url.path), "Deleting a service cannot resurrect its queued log")

        let model = makeModel(); self.model = model
        let service = config("Burst", "Tests", "printf '\\360\\237'; sleep 0.15; printf '\\237\\242\\n'; i=0; while ((i<500)); do echo row-$i; ((i++)); done; echo 'fatal: final diagnostic'; exit 3")
        model.upsert(service); model.start(service)
        for _ in 0..<60 {
            if model.logs[service.id]?.contains("fatal: final diagnostic") == true && !model.state(for: service).terminalActive { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let output = model.logs[service.id] ?? ""
        expect(output.contains("🟢") && output.contains("row-499") && output.contains("fatal: final diagnostic"), "Real process exit preserves Unicode and final burst output")
        expect(model.errors[service.id]?.contains("final diagnostic") == true, "Exit diagnostics see the final batched output")
        let removedModel = PortkeeperModel(supportDirectory: folder, runner: Bundle.main.resourceURL!.appendingPathComponent("portkeeper-runner"), monitoring: false)
        self.model = removedModel
        let removed = config("Removed", "Tests", "echo pending-output; sleep 5")
        removedModel.upsert(removed); removedModel.start(removed)
        try? await Task.sleep(nanoseconds: 50_000_000)
        removedModel.delete(removed)
        try? await Task.sleep(nanoseconds: 600_000_000)
        expect(removedModel.logs[removed.id] == nil && !FileManager.default.fileExists(atPath: folder.appendingPathComponent("Logs/\(removed.id.uuidString).log").path), "Deleting a running service discards pending output and termination writes")
        print("All output delivery tests passed.")
    }
}
