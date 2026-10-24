import AppKit
import NotchworkKit

extension TerminalWorkspaceTests {
    @MainActor static func runNotchworkPageTests() async {
        let model = makeModel()
        let ui = model.notchworkPages
        let original = config("Original", "Project", "echo original")
        model.configs = [original]
        func act(_ op: String, fields: [String: String]? = nil, extra: [String: Any] = [:]) -> Bool {
            var payload: [String: Any] = ["op": op, "token": ui.token]
            if let fields { payload["fields"] = fields }; payload.merge(extra) { _, new in new }
            return ui.perform(payload)
        }
        var workspaceOpened = false
        model.openNotchworkPage = { _, _ in workspaceOpened = true }
        ui.show("serviceActions", id: original.id.uuidString)
        expect(act("edit") && ui.page == "serviceEditor", "Service editor opens inside the hosted notch")
        expect(!workspaceOpened, "Editor navigation never opens the native workspace")
        expect(PortkeeperNotchworkUI.interface(model).keepOpen == true, "Forms keep the shared container open")
        expect(ui.fields["command"] == original.command, "Existing commands are editable in the notch")
        expect(act("save", fields: ["port": "99999"]) && !ui.error.isEmpty && model.configs == [original], "Invalid ports remain in the editor without saving")
        let oldToken = ui.token
        expect(act("save", fields: ["name": "Updated", "port": "8080"]) && ui.page == "dashboard", "Save commits the editor and returns to services")
        expect(model.configs[0].name == "Updated" && model.configs[0].port == 8080, "Saved fields reach the real configuration model")
        expect(!ui.perform(["op": "delete", "token": oldToken]), "Old-page actions cannot delete a service")
        ui.edit(model.configs[0], existing: true)
        _ = act("draft", fields: ["name": "Unsaved"])
        let interface = PortkeeperNotchworkUI.interface(model)
        expect(interface.stateJSON!.contains("Unsaved"), "Drafts survive host reattachment through app-owned state")
        _ = act("back")
        expect(model.configs[0].name == "Updated", "Cancel leaves saved configuration unchanged")
        ui.show("projectActions", id: "Project"); _ = act("rename")
        expect(ui.page == "projectEditor", "Project rename remains in the notch")
        _ = act("save", fields: ["name": "Renamed"])
        expect(model.configs[0].group == "Renamed", "Project rename updates service membership")
        ui.show("projectActions", id: "Renamed"); _ = act("remove")
        expect(ui.page == "projectDelete" && model.configs.count == 1, "Project removal requires its confirmation page")
        _ = act("back")
        expect(model.configs.count == 1, "Cancel project removal is non-destructive")
        ui.show("handoff"); _ = act("paste")
        _ = act("review", fields: ["json": "not json"])
        expect(ui.page == "pasteJSON" && !ui.error.isEmpty, "Invalid handoff shows the original parser error in the notch")
        let manifest: [String: Any] = ["version": 1, "project": "Imported", "services": [["name": "Worker", "directory": NSTemporaryDirectory(), "command": "echo " + String(repeating: "x", count: 1800)]]]
        var json = String(data: try! JSONSerialization.data(withJSONObject: manifest), encoding: .utf8)!
        json += String(repeating: " ", count: 80_000)
        _ = act("review", fields: ["json": json])
        expect(ui.page == "importReview" && model.configs.count == 1, "Large pasted handoff is reviewed before anything is imported")
        try! PortkeeperNotchworkUI.interface(model).validate()
        _ = act("importOnly")
        expect(model.configs.count == 2 && model.configs.contains { $0.group == "Imported" }, "Import only saves the reviewed services")
        expect(model.configs.allSatisfy { !model.state(for: $0).terminalActive }, "Import only never starts a command")
        expect(!act("importStart"), "Repeated import cannot start services after leaving review")
        ui.show("serviceActions", id: original.id.uuidString); _ = act("remove")
        expect(model.configs.count == 2, "Service removal waits for confirmation")
        _ = act("delete")
        expect(!model.configs.contains { $0.id == original.id }, "Confirmed removal deletes only the selected service")
        let listener = Listener(pid: 999_999, process: "fixture", address: "127.0.0.1:45678", port: 45678)
        model.listeners = [listener]; ui.confirm(listener); model.listeners = []
        _ = act("stop")
        expect(ui.page == "stopListener" && !ui.error.isEmpty, "Stale listener confirmation cannot target a changed process")
        let defaults = UserDefaults(suiteName: "notch-pages-\(UUID().uuidString)")!
        ui.terminalState = TerminalWorkspaceState(defaults: defaults)
        let imported = model.configs[0]; ui.activate(imported.id, open: true)
        expect(ui.page == "terminals", "Active terminal opens inside the shared container")
        expect(act("input", fields: ["input": "hello"], extra: ["id": imported.id.uuidString]) && !ui.error.isEmpty, "Inactive terminals reject input without launching a shell")
        _ = act("unpin", extra: ["id": imported.id.uuidString])
        expect(ui.terminalState!.activeTerminals.isEmpty, "Removing an active terminal leaves services untouched")
        ui.dashboard()
        expect(PortkeeperNotchworkUI.interface(model).keepOpen == false, "Dashboard restores normal hover collapse")
        print("All hosted Portkeeper page tests passed.")
    }
}
