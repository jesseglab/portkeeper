import Foundation
import WebKit
import AppKit
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
        let initialInterface = PortkeeperNotchworkUI.interface(model)
        expect(initialInterface.width == 400 && initialInterface.height == 590, "Dashboard requests the original content dimensions")
        model.notchworkTab = "ports"
        let updatedInterface = PortkeeperNotchworkUI.interface(model)
        expect(updatedInterface.html == initialInterface.html && updatedInterface.stateJSON != initialInterface.stateJSON, "Changing live state does not replace the dashboard document")
        expect(NotchworkBridge.perform("ui", value: #"{"tab":"services","query":"API"}"#, model: model), "Dashboard tab and filter are owned by the app")
        expect(model.notchworkTab == "services" && model.notchworkSearch == "API", "Tab and filter state persists through updates")
        expect(!NotchworkBridge.perform("ui", value: #"{"tab":"shell","query":""}"#, model: model), "Unknown UI routes are rejected")
        var opened: (String, String)?
        model.openNotchworkPage = { opened = ($0, $1) }
        let more = "{\"op\":\"more\",\"id\":\"" + service.id.uuidString + "\"}"
        expect(NotchworkBridge.perform("service", value: more, model: model), "Service menu opens its hosted action page")
        expect(opened == nil && model.notchworkPages.page == "serviceActions" && model.notchworkPages.identity == service.id.uuidString, "Hosted routes preserve service identity without opening another window")
        model.notchworkPages.dashboard()
        expect(!NotchworkBridge.perform("listener", value: #"{"op":"stop","id":"unknown"}"#, model: model), "Stopping listeners requires a current identity and native confirmation")
        model.configs = (0..<25).map { config("Worker \($0)", "Project", "private-command") }
        let many = PortkeeperNotchworkUI.interface(model)
        let state = try! JSONSerialization.jsonObject(with: Data(many.stateJSON!.utf8)) as! [String: Any]
        expect((state["services"] as? [[String: Any]])?.count == 25, "Dashboard includes services beyond the previous twelve-item truncation")
        expect(many.stateJSON!.contains("private-command"), "Dashboard preserves the original command subtitle")
        model.configs = [service]
        await checkDashboardDocument(model)
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
        expect(!text.contains("SECRET_TOKEN"), "Dashboard excludes private logs until output is explicitly opened")
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

private final class DashboardMessageSink: NSObject, WKScriptMessageHandler {
    var receive: ((String, String) -> Void)?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: String], let action = body["action"], let value = body["value"] { receive?(action, value) }
    }
}
extension TerminalWorkspaceTests {
    @MainActor static func checkDashboardDocument(_ model: PortkeeperModel) async {
        let interface = PortkeeperNotchworkUI.interface(model)
        let sink = DashboardMessageSink()
        sink.receive = { action, value in _ = NotchworkBridge.perform(action, value: value, model: model) }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(sink, name: "dashboard")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 590), configuration: configuration)
        let window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = web; window.orderFrontRegardless()
        defer { configuration.userContentController.removeScriptMessageHandler(forName: "dashboard"); window.orderOut(nil); window.contentView = nil }
        web.loadHTMLString("<style>html,body{margin:0;background:#000;color:white;color-scheme:dark}*{box-sizing:border-box}</style><script>window.notchwork={invoke:(action,value)=>window.webkit.messageHandlers.dashboard.postMessage({action,value})}</script>" + interface.html, baseURL: nil)
        do {
            for _ in 0..<50 {
                if (try? await web.evaluateJavaScript("typeof render")) as? String == "function" { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            _ = try await web.evaluateJavaScript("window.dispatchEvent(new CustomEvent('notchwork:state',{detail:" + interface.stateJSON! + "}))")
            let title = try await web.evaluateJavaScript("document.querySelector('h1').textContent") as? String
            expect(title == "portkeeper_", "Real dashboard document renders the original header")
            _ = try await web.evaluateJavaScript("document.querySelector('[data-tab=ports]').click()")
            for _ in 0..<20 where model.notchworkTab != "ports" { try await Task.sleep(nanoseconds: 50_000_000) }
            expect(model.notchworkTab == "ports", "Real Ports tab sends its state through the app action handler")
            let hidden = try await web.evaluateJavaScript("document.getElementById('services').hidden && !document.getElementById('ports').hidden") as? Bool
            expect(hidden == true, "Switching tabs displays the actual Ports pane")
            _ = try await web.evaluateJavaScript("document.getElementById('query').value='Backend';document.getElementById('query').dispatchEvent(new Event('input'))")
            for _ in 0..<20 where model.notchworkSearch != "Backend" { try await Task.sleep(nanoseconds: 50_000_000) }
            expect(model.notchworkSearch == "Backend", "Real port filter persists through the bridge")
            _ = try await web.evaluateJavaScript("window.dispatchEvent(new CustomEvent('notchwork:state',{detail:" + PortkeeperNotchworkUI.interface(model).stateJSON! + "}))")
            let query = try await web.evaluateJavaScript("document.getElementById('query').value") as? String
            expect(query == "Backend", "Live state refresh preserves the selected port filter")
            func push() async throws {
                let content = PortkeeperNotchworkUI.interface(model)
                web.setFrameSize(NSSize(width: content.width!, height: content.height))
                window.setContentSize(web.frame.size)
                _ = try await web.evaluateJavaScript("window.dispatchEvent(new CustomEvent('notchwork:state',{detail:" + content.stateJSON! + "}))")
            }
            func click(_ selector: String) async throws {
                _ = try await web.evaluateJavaScript("document.querySelector(" + String(data: try JSONEncoder().encode(selector), encoding: .utf8)! + ").click()")
                try await Task.sleep(nanoseconds: 200_000_000)
                try await push()
            }
            func screenshot(_ name: String) async throws {
                guard let folder = ProcessInfo.processInfo.environment["PARITY_SCREENSHOT_DIRECTORY"] else { return }
                try await Task.sleep(nanoseconds: 150_000_000)
                let image = try await web.takeSnapshot(configuration: nil)
                if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
                }
            }
            try await click("[data-tab=services]")
            try await screenshot("parity-dashboard")
            try await click("[data-action=service][data-op=more]")
            expect(model.notchworkPages.page == "serviceActions", "Real service menu stays inside the notch document")
            try await click("[data-page=edit]")
            expect(model.notchworkPages.page == "serviceEditor", "Real Edit button opens all editor fields")
            _ = try await web.evaluateJavaScript("document.querySelector('[name=name]').focus();document.querySelector('[name=name]').value='Draft Worker';document.querySelector('[name=name]').dispatchEvent(new Event('input',{bubbles:true}))")
            try await Task.sleep(nanoseconds: 350_000_000)
            try await push()
            let webResult0 = try await web.evaluateJavaScript("document.querySelector('[name=name]').value") as? String
            expect(webResult0 == "Draft Worker", "Live refresh preserves editor draft")
            let webResult1 = try await web.evaluateJavaScript("document.activeElement.name") as? String
            expect(webResult1 == "name", "Live refresh preserves editor focus")
            try await screenshot("parity-editor")
            try await click("[data-page=back]")
            expect(model.configs[0].name == "Worker", "Real Cancel does not save the draft")
            try await click("[data-action=open][data-op=handoff]")
            try await screenshot("parity-handoff")
            try await click("[data-page=paste]")
            let json = "{\"version\":1,\"project\":\"Fixture\",\"services\":[{\"name\":\"Preview\",\"directory\":\"/private/tmp\",\"command\":\"echo preview\"}]}"
            let quoted = String(data: try JSONEncoder().encode(json), encoding: .utf8)!
            _ = try await web.evaluateJavaScript("document.querySelector('[name=json]').value=" + quoted + ";document.querySelector('[name=json]').dispatchEvent(new Event('input',{bubbles:true}))")
            try await screenshot("parity-paste")
            try await click("[data-page=review]")
            expect(model.notchworkPages.page == "importReview", "Real review button reaches the existing handoff parser")
            expect(model.configs.count == 1, "Review cannot import or run a service")
            try await screenshot("parity-import-review")
            try await click("[data-page=back]")
            model.logs[model.configs[0].id] = "[ready] Worker is ready\n[info] Waiting for requests\n[warning] Example warning"
            try await click("[data-action=service][data-op=more]")
            try await click("[data-page=output]")
            try await screenshot("parity-output")
            let webResult2 = try await web.evaluateJavaScript("document.querySelector('[data-log-query=output]')!==null") as? Bool
            expect(webResult2 == true, "Hosted output retains search, filters, wrapping, copy, and follow controls")
            try await click("[data-page=back]")
            model.notchworkPages.terminalState = TerminalWorkspaceState(defaults: UserDefaults(suiteName: "web-parity-\(UUID().uuidString)")!)
            try await click("[data-action=service][data-op=terminal]")
            expect(model.notchworkPages.page == "terminals", "Real terminal button opens hosted terminal controls")
            try await screenshot("parity-terminals")
            model.notchworkPages.dashboard(); try await push()

        } catch { expect(false, "Real dashboard WebKit check: \(error)") }
        model.notchworkTab = "services"; model.notchworkSearch = ""
    }
}
