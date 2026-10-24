import AppKit
import UniformTypeIdentifiers

/// App-owned navigation and drafts. The shared host only renders this state and delivers actions.
@MainActor final class PortkeeperNotchworkPages {
    unowned let model: PortkeeperModel
    private(set) var page = "dashboard"
    private(set) var token = UUID().uuidString
    private(set) var identity = ""
    private(set) var fields: [String: String] = [:]
    private(set) var fieldRevision = 0
    private(set) var error = ""
    private(set) var busy = false
    private var pendingImport: ImportedProject?
    private var pendingListener: Listener?
    private var editingID: UUID?
    private var editingExisting = false
    private var terminalInputs: [String: String] = [:]
    private var pasteFields: [String: String] = [:]
    var terminalState: TerminalWorkspaceState?
    var detachTerminal: ((ServiceConfig) -> Void)?
    var settings: (() -> Void)?
    init(model: PortkeeperModel) { self.model = model }
    var size: NSSize {
        switch page {
        case "serviceEditor": return NSSize(width: 460, height: 510)
        case "serviceActions": return NSSize(width: 420, height: 400)
        case "projectActions", "handoff": return NSSize(width: 420, height: 350)
        case "serviceDelete", "projectEditor", "projectDelete", "stopListener", "settings": return NSSize(width: 420, height: 290)
        case "stopResult": return NSSize(width: 420, height: 210)
        case "output": return NSSize(width: 620, height: 480)
        case "terminals": return NSSize(width: 620, height: 590)
        case "pasteJSON", "importReview": return NSSize(width: 560, height: 510)
        default: return NSSize(width: 400, height: 590)
        }
    }
    private func changed() { model.objectWillChange.send() }
    func show(_ next: String, id: String = "", draft: [String: String] = [:]) {
        if page == "pasteJSON" { pasteFields = fields }
        page = next; identity = id; fields = draft; token = UUID().uuidString
        error = ""; busy = false; fieldRevision += 1; changed()
    }
    func dashboard(ports: Bool = false) {
        pendingImport = nil; pendingListener = nil
        if ports { model.notchworkTab = "ports" }
        show("dashboard")
    }
    func edit(_ config: ServiceConfig, existing: Bool) {
        editingID = config.id; editingExisting = existing
        show("serviceEditor", id: config.id.uuidString, draft: ["name": config.name, "group": config.group,
            "directory": config.directory, "command": config.command, "port": config.port.map(String.init) ?? "", "url": config.url])
    }
    func add(group: String = "My services") {
        edit(ServiceConfig(name: "", group: group, directory: "", command: "", port: nil, url: ""), existing: false)
    }
    func confirm(_ listener: Listener) { pendingListener = listener; show("stopListener", id: listener.id) }
    func review(_ project: ImportedProject) { pendingImport = project; show("importReview") }
    func activate(_ id: UUID, open: Bool) {
        terminalState?.activeTerminals.insert(id)
        if open { show("terminals", id: id.uuidString) } else { dashboard(); model.notchworkNotice = "Terminal made active" }
    }
    var snapshot: [String: Any] {
        var result: [String: Any] = ["page": page, "token": token, "identity": identity, "fields": fields,
            "fieldRevision": fieldRevision, "error": error, "busy": busy, "connection": model.notchworkStatus]
        if let id = UUID(uuidString: identity), let config = model.configs.first(where: { $0.id == id }) {
            result["name"] = config.name; result["group"] = config.group
            if page == "serviceDelete" { result["command"] = config.command }
            if page == "output" { result["output"] = PortkeeperModel.readableOutput(model.logs[id] ?? "") }
        }
        if page == "serviceEditor" { result["isNew"] = !editingExisting }
        if page.hasPrefix("project") {
            let members = model.configs.filter { $0.group == identity }
            result["count"] = members.count; result["running"] = members.filter { model.state(for: $0).terminalActive }.count
        }
        if page == "stopListener", let listener = pendingListener {
            result["process"] = listener.process; result["pid"] = listener.pid; result["address"] = listener.address
            result["managed"] = model.managedService(for: listener)?.name ?? ""
            result["otherPorts"] = Array(Set(model.listeners.filter { $0.pid == listener.pid && $0.port != listener.port }.map(\.port))).sorted()
        }
        if page == "importReview", let project = pendingImport {
            result["name"] = project.name
            result["importServices"] = project.services.map { config -> [String: Any] in
                ["name": config.name, "command": config.command, "directory": config.directory,
                 "port": config.port.map { port in model.listeners.first(where: { $0.port == port }).map { ":\(port) · \($0.process)" } ?? ":\(port)" } ?? "No port"]
            }
        }
        if page == "terminals" {
            let active = terminalState?.activeTerminals ?? []
            result["available"] = model.configs.map { ["id": $0.id.uuidString, "name": $0.group + " / " + $0.name] }
            result["fontSize"] = terminalState?.preferences.fontSize ?? 11
            result["terminals"] = model.configs.filter { active.contains($0.id) }.map { config -> [String: Any] in
                ["id": config.id.uuidString, "name": config.name, "group": config.group,
                 "output": PortkeeperModel.readableOutput(model.logs[config.id] ?? ""),
                 "active": model.state(for: config).terminalActive, "input": model.acceptsInput(config.id),
                 "inputDraft": terminalInputs[config.id.uuidString] ?? "", "command": config.command, "port": config.port.map(String.init) ?? "",
                 "status": model.state(for: config).terminalLabel, "issue": model.state(for: config).terminalIssue,
                 "collapsed": terminalState?.preferences.collapsed.contains(config.id) ?? false,
                 "color": terminalState?.colorIndex(config.id) ?? 0]
            }
        }
        return result
    }
    private func fail(_ message: String) { error = message; busy = false; changed() }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    private func brief() throws -> String {
        guard let url = Bundle.main.url(forResource: "Portkeeper-setup", withExtension: "md") else { throw ImportError.message("The setup brief is missing. Reinstall Portkeeper.") }
        return try String(contentsOf: url, encoding: .utf8)
    }
    private func chooseFolder(_ field: String) {
        let current = token; busy = true; changed()
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        picker.begin { [weak self] response in
            guard let self, self.token == current else { return }
            self.busy = false
            if response == .OK, let url = picker.url { self.fields[field] = url.path; self.fieldRevision += 1; self.error = "" }
            self.changed()
        }
    }
    private func chooseManifest() {
        let current = token; busy = true; changed()
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.json]; picker.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        picker.begin { [weak self] response in
            guard let self, self.token == current else { return }
            self.busy = false
            if response == .OK, let url = picker.url {
                do { self.review(try ImportedProject.load(from: url)) } catch { self.fail(error.localizedDescription) }
            }
            self.changed()
        }
    }
    private func saveBrief() {
        do {
            let text = try brief(), current = token
            let picker = NSSavePanel(); picker.nameFieldStringValue = "Portkeeper-setup.md"; picker.allowedContentTypes = [.plainText]
            busy = true; changed(); NSApp.activate(ignoringOtherApps: true)
            picker.begin { [weak self] response in
                guard let self, self.token == current else { return }
                self.busy = false
                if response == .OK, let url = picker.url {
                    do { try text.write(to: url, atomically: true, encoding: .utf8); self.model.notchworkNotice = "Setup brief saved" }
                    catch { self.fail(error.localizedDescription) }
                }
                self.changed()
            }
        } catch { fail(error.localizedDescription) }
    }
    @discardableResult func perform(_ payload: [String: Any]) -> Bool {
        guard payload["token"] as? String == token, let op = payload["op"] as? String, !busy else { return false }
        if let draft = payload["fields"] as? [String: String] {
            let allowed: Set<String>
            switch page {
            case "serviceEditor": allowed = ["name", "group", "directory", "command", "port", "url"]
            case "projectEditor": allowed = ["name"]
            case "pasteJSON": allowed = ["json", "baseDirectory"]
            case "terminals": allowed = ["input"]
            default: allowed = []
            }
            guard Set(draft.keys).isSubset(of: allowed), draft.values.allSatisfy({ $0.utf8.count <= 1_000_000 }) else { return false }
            fields.merge(draft) { _, new in new }
        }
        if page == "terminals", let id = payload["id"] as? String, !id.isEmpty, let input = (payload["fields"] as? [String: String])?["input"] { terminalInputs[id] = input }
        if op == "copyOutput", ["output", "terminals"].contains(page), let text = payload["text"] as? String, text.utf8.count <= 200_000 { copy(text); model.notchworkNotice = "Output copied"; return true }
        if op == "draft" { error = ""; changed(); return true }
        if op == "back" { dashboard(); return true }
        if op == "ports" { dashboard(ports: true); return true }
        if op == "handoff", page == "pasteJSON" || page == "importReview" { show("handoff"); return true }
        if op == "scanAI" { if let scan = model.scanError { copy(PortkeeperModel.scanIssuePrompt(scan)); model.notchworkNotice = "Port scan prompt copied" }; return true }
        switch page {
        case "serviceActions":
            guard let id = UUID(uuidString: identity), let config = model.configs.first(where: { $0.id == id }) else { fail("This service was removed."); return false }
            switch op {
            case "edit": edit(config, existing: true)
            case "output": show("output", id: identity)
            case "restart": model.restart(config); dashboard()
            case "activate": activate(id, open: false)
            case "remove": show("serviceDelete", id: identity)
            default: return false
            }
        case "serviceEditor":
            if op == "browse" { chooseFolder("directory"); return true }
            guard op == "save", let id = editingID else { return false }
            let trim: (String) -> String = { (self.fields[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            guard ["name", "group", "directory", "command"].allSatisfy({ !trim($0).isEmpty }) else { fail("Name, group, project folder, and command are required."); return true }
            let portText = trim("port")
            guard portText.isEmpty || Int(portText).map({ (1...65535).contains($0) }) == true else { fail("Expected port must be between 1 and 65535, or empty."); return true }
            guard !editingExisting || model.configs.contains(where: { $0.id == id }) else { fail("This service was removed while you were editing."); return true }
            let config = ServiceConfig(id: id, name: trim("name"), group: trim("group"), directory: trim("directory"), command: trim("command"), port: Int(portText), url: trim("url"))
            model.upsert(config); model.notchworkNotice = "\(config.name) saved"; dashboard()
        case "serviceDelete":
            guard op == "delete", let id = UUID(uuidString: identity), let config = model.configs.first(where: { $0.id == id }) else { return false }
            model.delete(config); model.notchworkNotice = "\(config.name) removed"; dashboard()
        case "projectActions":
            guard model.configs.contains(where: { $0.group == identity }) else { fail("This project was removed."); return false }
            switch op {
            case "add": add(group: identity)
            case "restart": model.restartGroup(identity); dashboard()
            case "rename": show("projectEditor", id: identity, draft: ["name": identity])
            case "remove": show("projectDelete", id: identity)
            default: return false
            }
        case "projectEditor":
            guard op == "save" else { return false }
            let name = (fields["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80, !model.configs.contains(where: { $0.group != identity && $0.group.caseInsensitiveCompare(name) == .orderedSame }) else { fail("Use a unique name of up to 80 characters."); return true }
            model.renameGroup(identity, to: name); model.notchworkNotice = "Project renamed"; dashboard()
        case "projectDelete":
            guard op == "delete" else { return false }
            model.deleteGroup(identity); model.notchworkNotice = "\(identity) removed"; dashboard()
        case "handoff":
            switch op {
            case "copy": do { copy(try brief()); model.notchworkNotice = "Setup brief copied"; dashboard() } catch { fail(error.localizedDescription) }
            case "saveBrief": saveBrief()
            case "paste": show("pasteJSON", draft: pasteFields)
            case "importFile": chooseManifest()
            default: return false
            }
        case "pasteJSON":
            switch op {
            case "paste": if let text = NSPasteboard.general.string(forType: .string) {
                guard text.utf8.count <= 1_000_000 else { fail("Project JSON must be at most 1 MB."); return true }
                fields["json"] = text; fieldRevision += 1; error = ""; changed()
            }
            case "browse": chooseFolder("baseDirectory")
            case "review":
                do {
                    let base = fields["baseDirectory"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
                    review(try ImportedProject.paste(fields["json"] ?? "", baseDirectory: base))
                } catch { fail(error.localizedDescription) }
            default: return false
            }
        case "importReview":
            if op == "editPaste" { show("pasteJSON", draft: pasteFields); return true }
            guard ["importOnly", "importStart"].contains(op), let project = pendingImport else { return false }
            pendingImport = nil; model.importProject(project, startImmediately: op == "importStart")
            model.notchworkNotice = model.importStatus ?? "Project imported"
            pasteFields = [:]; model.notchworkTab = "services"; dashboard()
        case "stopListener":
            guard op == "stop", let listener = pendingListener else { return false }
            guard model.listeners.contains(listener) else { fail("This listener has changed. Refresh the Ports list before trying again."); return true }
            busy = true; changed(); let current = token
            Task { [weak self] in
                guard let self else { return }
                let message = await self.model.stopListener(listener)
                if self.token == current { self.show("stopResult", draft: ["message": message]) }
            }
        case "output":
            guard let id = UUID(uuidString: identity), let config = model.configs.first(where: { $0.id == id }) else { return false }
            switch op {
            case "ai": copy(PortkeeperModel.troubleshootingPrompt(for: config, output: model.logs[id] ?? "")); model.notchworkNotice = "AI prompt copied"
            case "pin": model.openNotchworkPage?("terminal", identity)
            default: return false
            }
        case "terminals":
            if op == "addAll" { terminalState?.activeTerminals.formUnion(model.configs.filter { model.state(for: $0).terminalActive }.map(\.id)); changed(); return true }
            if op == "add", let id = (payload["id"] as? String).flatMap(UUID.init(uuidString:)), model.configs.contains(where: { $0.id == id }) { terminalState?.activeTerminals.insert(id); changed(); return true }
            if op == "font", let size = payload["size"] as? Double, (9...18).contains(size) { terminalState?.preferences.fontSize = size; changed(); return true }
            let id = (payload["id"] as? String).flatMap(UUID.init(uuidString:))
            guard let id, terminalState?.activeTerminals.contains(id) == true, let config = model.configs.first(where: { $0.id == id }) else { return false }
            switch op {
            case "input": if let message = model.sendInput(terminalInputs[id.uuidString] ?? "", to: id) { fail(message) } else { terminalInputs[id.uuidString] = ""; fields["input"] = ""; fieldRevision += 1; changed() }
            case "collapse": terminalState?.toggleCollapsed(id); changed()
            case "color": if let color = payload["color"] as? Int, TerminalPalette.names.indices.contains(color) { terminalState?.preferences.colors[id] = color; changed() }
            case "unpin": terminalState?.activeTerminals.remove(id); changed()
            case "detach": detachTerminal?(config)
            case "workspace": model.openNotchworkPage?("terminal", id.uuidString)
            case "start": model.start(config)
            case "stop": model.stop(config)
            case "restart": model.restart(config)
            case "ai": copy(PortkeeperModel.troubleshootingPrompt(for: config, output: model.logs[id] ?? "")); model.notchworkNotice = "AI prompt copied"
            default: return false
            }
        case "settings":
            switch op {
            case "retry": Task { do { try await model.presentNotchwork() } catch { self.fail(error.localizedDescription) } }
            case "hostSettings": settings?()
            case "quit": NSApplication.shared.terminate(nil)
            default: return false
            }
        default: return false
        }
        changed(); return true
    }
}
