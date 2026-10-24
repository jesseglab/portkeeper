import Foundation
import NotchworkKit

extension TerminalWorkspaceTests {
    @MainActor static func runNotchworkBridgeTests() async {
        expect(NotchworkBridge.priority(issues: 1, starting: 1).rank == 2, "Issues take high priority over startup")
        expect(NotchworkBridge.priority(issues: 0, starting: 1).rank == 1, "Starting services send mid priority")
        expect(NotchworkBridge.priority(issues: 0, starting: 0).rank == 0, "Healthy and idle services send low priority")
        let model = makeModel()
        let service = config("Worker", "API bridge", "sleep 10")
        model.configs = [service]
        model.logs[service.id] = "SECRET_TOKEN=should-not-leave-portkeeper"
        let fake = NotchworkClient(connection: .init(endpoint: "http://127.0.0.1:1", token: "test"))
        var commands: [HostCommand] = []
        var generation = 1
        var failConnection = false
        let bridge = NotchworkBridge(model: model, connect: {
            NotchworkClient(connection: .init(endpoint: fake.connection.endpoint, token: "test-\(generation)"))
        }, send: { _, command in
            if command.operation == "events" {
                try await Task.sleep(nanoseconds: 30_000_000)
                if failConnection { failConnection = false; throw ActivityError.invalid("Test disconnect") }
            } else { commands.append(command) }
            return HostResponse(ok: true, message: "Test", events: [])
        })
        defer { bridge.stop() }
        try? await Task.sleep(nanoseconds: 150_000_000)
        expect(commands.first?.operation == "register", "Bridge registers its UI before publication")
        expect(commands.first?.registration?.customInterface == true, "Registration declares the app-owned interface")
        expect(commands.contains { $0.operation == "publish" }, "Portkeeper publishes directly through the API")
        expect(!NotchworkBridge.perform("run-shell", value: "echo unsafe", model: model), "Unknown custom actions cannot execute commands")
        expect(!NotchworkBridge.perform("service.start", value: UUID().uuidString, model: model), "Custom actions reject unknown service identities")
        expect(NotchworkBridge.perform("service.start", value: service.id.uuidString, model: model), "Custom UI callback starts a real managed service")
        for _ in 0..<50 {
            if case .running = model.state(for: service) { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        bridge.update(force: true)
        try? await Task.sleep(nanoseconds: 150_000_000)
        let card = commands.last(where: { $0.operation == "publish" })!.activity!
        expect(card.sourceID == "app.portkeeper" && card.details.first?.contains("Running") == true, "API publication reflects running managed services")
        expect(card.interface != nil, "Portkeeper supplies its own interface")
        let text = String(data: try! JSONEncoder().encode(card), encoding: .utf8)!
        expect(!text.contains("SECRET_TOKEN") && !text.contains("sleep 10"), "API excludes logs and commands")
        let before = commands.filter { $0.operation == "publish" }.count
        bridge.update()
        try? await Task.sleep(nanoseconds: 100_000_000)
        expect(commands.filter { $0.operation == "publish" }.count == before, "Unchanged model does not republish")
        model.errors[service.id] = "SECRET_TOKEN=private diagnostic"
        bridge.update(force: true)
        try? await Task.sleep(nanoseconds: 100_000_000)
        expect(commands.last(where: { $0.operation == "publish" })?.activity?.priority == .high, "Service failure sends high priority")
        try! await bridge.present()
        expect(commands.suffix(3).map(\.operation) == ["register", "publish", "present"], "Explicit opening uses the host API, never a local notch")
        generation = 2; failConnection = true
        try? await Task.sleep(nanoseconds: 5_300_000_000)
        expect(commands.filter { $0.operation == "register" }.count >= 3, "Bridge re-registers after host reconnect")
        expect(NotchworkBridge.perform("service.stop", value: service.id.uuidString, model: model), "Custom UI callback stops its service")
        bridge.stop()
        try? await Task.sleep(nanoseconds: 100_000_000)
        expect(commands.last?.operation == "remove", "Shutdown removes Portkeeper from the shared host")
        print("All Notchwork API bridge tests passed.")
    }
}
