import AppKit
import Foundation
import SwiftUI

@main struct TerminalWorkspaceTests {
    @MainActor static var controller: TerminalWorkspaceController?
    @MainActor static var model: PortkeeperModel?
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { if let model { for config in model.configs { model.stop(config) } }; fputs("FAIL: \(message)\n", stderr); exit(1) }
        print("PASS: \(message)")
    }
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; menu.addItem(item); app.mainMenu = menu
        Task { @MainActor in
            if CommandLine.arguments.contains("--preview") { preview() }
            else if CommandLine.arguments.contains("--porty-preview") { previewPorty() }
            else if CommandLine.arguments.contains("--performance") { await runPerformanceProbe(); app.terminate(nil) }
            else { await runRuntimeTests(); await runNotchworkBridgeTests(); await runPortyTests(); await runTests(); await runNotchTests(); await runOutputDeliveryTests(); app.terminate(nil) }
        }
        app.run()
    }
    @MainActor static func makeModel() -> PortkeeperModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portkeeper-test-\(UUID().uuidString)")
        return PortkeeperModel(supportDirectory: directory, runner: Bundle.main.resourceURL!.appendingPathComponent("portkeeper-runner"), monitoring: false)
    }
    static func config(_ name: String, _ group: String, _ command: String = "printf '\\033[32mready\\033[0m\\n'; while true; do printf 'heartbeat\\n'; sleep 1; done", port: Int? = nil) -> ServiceConfig {
        ServiceConfig(name: name, group: group, directory: "/tmp", command: command, port: port, url: "")
    }
    @MainActor static func runTests() async {
        let suite = "PortkeeperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = TerminalWorkspaceState(defaults: defaults)
        // Synthetic fixtures; the port is filter data, not a listener to bind.
        let a = config("API", "Example Project A", port: 49152), b = config("Web", "Example Project A"), c = config("Worker", "Example Project B"), d = config("Stopped", "Example Project B")
        let configs = [a,b,c,d]
        state.assignColors(configs)
        expect(Set(configs.map { state.colorIndex($0.id) }).count == 4, "Distinct stable service colors")
        state.pin(configs.map(\.id)); state.pin([a.id,b.id])
        expect(state.preferences.pinned.count == 4, "Pin all is idempotent")
        func status(_ config: ServiceConfig) -> ServiceState {
            if config.id == a.id { return .running }
            if config.id == b.id { return .starting }
            if config.id == c.id { return .unhealthy("warning") }
            return .stopped
        }
        state.status = .active
        expect(state.visible(configs, state: status).count == 3, "Active includes starting and unhealthy processes")
        state.status = .issues
        expect(state.visible(configs, state: status).map(\.id) == [c.id], "Issue filter")
        state.status = .all; state.project = "Example Project A"; state.search = "49152"
        expect(state.visible(configs, state: status).map(\.id) == [a.id], "Combined project and port filter")
        state.search = " no match "
        expect(state.visible(configs, state: status).isEmpty, "No-match filter")
        state.search = ""; state.project = "All projects"
        state.toggleCollapsed(a.id); state.preferences.density = .compact
        state.preferences.fontSize = 14; state.preferences.grouping = .status
        state.move(b.id, by: -1)
        let restored = TerminalWorkspaceState(defaults: defaults)
        expect(restored.preferences.pinned.first == b.id && restored.preferences.collapsed.contains(a.id), "Pin order and collapse persist")
        expect(restored.preferences.density == .compact && restored.preferences.fontSize == 14 && restored.preferences.grouping == .status, "Size, text size, and grouping persist")
        state.reconcile([a.id,c.id])
        expect(state.preferences.pinned.count == 2 && state.preferences.colors[b.id] == nil, "Deleted services are pruned")
        let ansi = "\u{1B}[32mready\u{1B}[0m\n\u{1B}[31mERROR connection failed\u{1B}[0m\nwarning retry\n100%\r20%\r30%\n"
        expect(TerminalOutput.filtered(ansi, query: "connection", level: .errors).contains("connection failed"), "Colored output search and error filter")
        expect(TerminalOutput.plain(TerminalOutput.filtered(ansi, query: "", level: .warnings)) == "warning retry", "Warning filter")
        expect(TerminalOutput.normalized("abc\rdef\r\nnext") == "def\nnext", "CR progress and CRLF normalization")
        let attributed = TerminalOutput.attributed(ansi, fontSize: 11)
        expect(!attributed.string.contains("\u{1B}"), "ANSI escape codes do not leak into terminal text")
        let green = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let red = attributed.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor
        expect(green != red, "ANSI foreground colors are rendered")
        expect(TerminalOutput.plain("\u{1B}]0;title\u{7}visible") == "visible", "Terminal title controls are stripped")
        let rgb = TerminalOutput.attributed("\u{1B}[38;2;20;100;200mRGB\u{1B}[0m plain", fontSize: 13)
        expect(rgb.string == "RGB plain", "Truecolor terminal output")
        let host = NSHostingView(rootView: TerminalLogView(output: "hello world\n"))
        let selectionWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
        selectionWindow.isReleasedWhenClosed = false
        selectionWindow.contentView = host
        selectionWindow.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 100_000_000)
        func textView(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.compactMap { textView(in: $0) }.first
        }
        let text = textView(in: host)
        expect(text != nil, "Native selectable terminal view mounts")
        text?.setSelectedRange(NSRange(location: 0, length: 5))
        host.rootView = TerminalLogView(output: "hello world\nnew output\n")
        try? await Task.sleep(nanoseconds: 100_000_000)
        expect(textView(in: host)?.selectedRange().length == 5, "Text selection survives arriving output")
        selectionWindow.close()
        let model = makeModel()
        self.model = model
        expect(model.configs.isEmpty && model.logs.isEmpty, "Fresh profile has no bundled services or logs")
        model.upsert(a); model.upsert(b)
        expect(model.start(a) && model.start(b), "Launch two real runner processes")
        for _ in 0..<30 {
            if (model.logs[a.id] ?? "").contains("heartbeat") && (model.logs[b.id] ?? "").contains("heartbeat") { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        expect((model.logs[a.id] ?? "").contains("heartbeat"), "Real process output reaches terminal model")
        let controller = TerminalWorkspaceController(model: model)
        self.controller = controller
        controller.show()
        expect(Set(controller.state.preferences.pinned) == [a.id,b.id], "Workspace pins all real active services")
        controller.state.unpin(a.id)
        expect(model.state(for: a).terminalActive, "Unpinning leaves the process running")
        controller.openDetached(a); controller.openDetached(a)
        expect(NSApp.windows.filter { $0.title == "API · Example Project A" }.count == 1, "Separate terminal window is reused")
        controller.state.keepOnTop = true
        expect(NSApp.windows.filter { $0.title.contains("Example Project A") || $0.title.contains("Terminal workspace") }.allSatisfy { $0.level == .floating }, "Keep-on-top applies to main and separate windows")
        for window in NSApp.windows where window.title.contains("Example Project A") || window.title.contains("Terminal workspace") { window.performClose(nil) }
        expect(model.state(for: a).terminalActive && model.state(for: b).terminalActive, "Closing windows leaves services running")
        model.stop(a); model.stop(b)
        for _ in 0..<30 {
            if !model.state(for: a).terminalActive && !model.state(for: b).terminalActive { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        expect(!model.state(for: a).terminalActive && !model.state(for: b).terminalActive, "Test processes shut down cleanly")
        print("All terminal workspace tests passed.")
    }
    @MainActor static func preview() {
        let model = makeModel()
        self.model = model
        // Generated console output only; these are not saved projects or real servers.
        let services = [
            config("API server", "Example Project A", "printf '\\033[36m[api]\\033[0m Server ready on localhost:49152\\n'; while true; do printf '\\033[32mGET\\033[0m /v1/projects 200 12ms\\n'; sleep 2; done"),
            config("Web frontend", "Example Project A", "printf '\\033[35mVITE v6.0\\033[0m ready in 184ms\\n  Local: http://localhost:49153/\\n'; while true; do printf '\\033[36m[hmr]\\033[0m page updated /src/App.tsx\\n'; sleep 3; done"),
            config("Job worker", "Example Project B", "while true; do printf '\\033[33mwarning\\033[0m retrying job after timeout\\nprocessed 12 jobs in 340ms\\n'; sleep 4; done"),
            config("Asset watcher", "Example Project B", "while true; do printf '\\033[32mbuilt\\033[0m 42 assets in 90ms\\n'; sleep 5; done")
        ]
        for service in services { model.upsert(service); model.start(service) }
        let controller = TerminalWorkspaceController(model: model)
        self.controller = controller
        controller.state.preferences.pinned = []
        controller.state.preferences.density = .comfortable
        controller.state.preferences.grouping = .project
        controller.state.activeTerminals = Set(services.map(\.id))
        controller.show()
    }
}
