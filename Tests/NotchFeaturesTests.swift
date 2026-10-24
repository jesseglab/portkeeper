import AppKit
import Foundation

extension TerminalWorkspaceTests {
    @MainActor static func runNotchTests() async {
        let json = """
        {"version":1,"project":"Example","services":[{"name":"API","directory":"/tmp","command":"echo ready","port":45123}]}
        """
        do {
            let parsed = try ImportedProject.paste(json)
            expect(parsed.name == "Example" && parsed.services.count == 1 && parsed.sourceURL == nil, "Pasted JSON uses import parser")
            let fenced = try ImportedProject.paste("```json\n" + json + "\n```")
            expect(fenced.services.first?.command == "echo ready", "Assistant JSON code blocks can be pasted")
            let relative = json.replacingOccurrences(of: "\"/tmp\"", with: "\".\"")
            do { _ = try ImportedProject.paste(relative); expect(false, "Relative paste requires a base folder") }
            catch { expect(error.localizedDescription.contains("choose a project folder"), "Relative paste requires a base folder") }
            let based = try ImportedProject.paste(relative, baseDirectory: URL(fileURLWithPath: "/tmp"))
            expect(based.services[0].directory == "/tmp", "Chosen folder resolves pasted relative paths")
            for invalid in ["{", json.replacingOccurrences(of: "45123", with: "99999"), json.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")] {
                do { _ = try ImportedProject.paste(invalid); expect(false, "Reject malformed manifest") } catch { }
            }
            expect(true, "Malformed JSON, invalid ports, and versions are rejected")
        } catch { expect(false, "JSON parsing: \(error)") }
        expect(TerminalOutput.filtered("ready\n[input] refresh\nerror: oops", query: "", level: .inputs) == "[input] refresh", "Input entries are separately filterable")
        expect(TerminalOutput.level("[input] error test") == .inputs, "Input text does not become an error entry")

        expect(PortkeeperModel.latestDiagnosticError(in: "[input] error: test\n$ echo error: test") == nil, "Input and command echoes do not trigger the issue beacon")
        expect(PortkeeperModel.latestDiagnosticError(in: "error: connection failed\n") != nil, "Actual service errors still trigger diagnostics")
        let suite = "PortkeeperEdgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = TerminalWorkspaceState(defaults: defaults)
        let id = UUID()
        workspace.activeTerminals.insert(id)
        expect(TerminalWorkspaceState(defaults: defaults).activeTerminals == [id], "Active terminal choices persist separately from workspace pins")
        workspace.reconcile([])
        expect(workspace.activeTerminals.isEmpty, "Deleted active terminals are removed from the drawer")

        let model = makeModel()
        self.model = model
        let echo = config("Input echo", "Input test", "printf 'input-ready\\n'; while IFS= read -r line; do printf 'received:%s\\n' \"$line\"; done")
        model.upsert(echo)
        expect(model.sendInput("hello", to: echo.id) != nil, "Stopped services reject input")
        expect(model.start(echo), "Input test starts")
        for _ in 0..<100 {
            if model.logs[echo.id]?.contains("input-ready\n") == true { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        expect(model.sendInput("hello", to: echo.id) == nil, "Running service accepts a line")
        for _ in 0..<40 {
            if model.logs[echo.id]?.contains("received:hello") == true { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        expect(model.logs[echo.id]?.contains("received:hello") == true, "Input reaches the real child process and output returns")
        expect(model.sendInput("one\ntwo", to: echo.id) != nil, "Multiline input is rejected")
        expect(model.sendInput(String(repeating: "x", count: 512), to: echo.id) != nil, "Oversized input is rejected without blocking")
        model.stop(echo)

        let stamp = FileManager.default.temporaryDirectory.appendingPathComponent("pk-restart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stamp) }
        let a = config("One", "Restart test", "echo one >> '\(stamp.path)'; while true; do sleep 1; done")
        let b = config("Two", "Restart test", "echo two >> '\(stamp.path)'; while true; do sleep 1; done")
        model.upsert(a); model.upsert(b)
        expect(model.start(a) && model.start(b), "Restart test starts two managed services")
        for _ in 0..<100 {
            if ((try? String(contentsOf: stamp)) ?? "").split(separator: "\n").count == 2 { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        model.restartGroup("Restart test")
        model.restartGroup("Restart test")
        for _ in 0..<120 {
            if !model.isRestartingGroup("Restart test") { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        for _ in 0..<100 {
            if ((try? String(contentsOf: stamp)) ?? "").split(separator: "\n").count >= 4 { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let launches = ((try? String(contentsOf: stamp)) ?? "").split(separator: "\n")
        if launches.count != 4 { print("Restart diagnostic:", launches.count, model.errors, model.restarting) }
        expect(launches.count == 4 && model.state(for: a).terminalActive && model.state(for: b).terminalActive, "Project restart replaces both processes exactly once, even after a repeated click")
        model.restart(a)
        model.stop(a)
        try? await Task.sleep(nanoseconds: 800_000_000)
        expect(!model.state(for: a).terminalActive && !model.restarting.contains(a.id), "Stop cancels a pending restart")
        model.stop(b)

        expect(!NSApp.windows.contains(where: { $0.title == "Portkeeper · Notch" || $0.title == "Portkeeper · Active terminals" }), "Portkeeper creates no notch or edge windows")
        print("All paste, restart, and terminal input tests passed.")
    }
}
