import AppKit
import SwiftUI
import UniformTypeIdentifiers

#if !PORTKEEPER_TEST
@main struct PortkeeperApp: App {
    @NSApplicationDelegateAdaptor(PortkeeperDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

#endif

enum PanelTab: String, CaseIterable { case services = "Services", ports = "Ports" }

struct PortkeeperPanel: View {
    @ObservedObject var model: PortkeeperModel
    @ObservedObject var route: PortkeeperPanelRoute
    var embedded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: PanelTab = .services
    @State private var handoffNotice: String?
    @State private var panelError: String?
    @State private var search = ""

    var body: some View {
        ZStack {
            PortkeeperBackdrop()
            pageContent
                .id(route.page)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: route.page)
        }
        .frame(width: route.page.size.width, height: embedded ? nil : route.page.size.height)
        .foregroundStyle(PortkeeperStyle.ivory)
        .tint(PortkeeperStyle.coral)
        .preferredColorScheme(.dark)
        .onChange(of: route.revision) { _, _ in tab = route.selectedTab }
    }

    @ViewBuilder private var pageContent: some View {
        switch route.page {
        case .dashboard:
            dashboard
        case .serviceEditor(let config):
            ServiceEditor(config: config, onCancel: { route.back() }, onSave: { saved in
                model.upsert(saved)
                handoffNotice = "\(saved.name) saved"
                route.back()
            })
            .id(config.id)
        case .serviceActions(let config):
            ServiceActionsPage(config: config, onBack: { route.back() },
                               onEdit: { editService(config) },
                               onOutput: { openOutput(config) },
                               onRestart: { model.restart(config); route.back() },
                               onActivate: { route.activateTerminal?(config.id); route.back() },
                               onRemove: { route.confirmServiceDelete(config) })
        case .serviceDelete(let config):
            DeleteServicePage(config: config, onCancel: { route.back() }, onDelete: {
                model.delete(config)
                handoffNotice = "\(config.name) removed"
                route.back()
            })
        case .projectEditor(let group):
            ProjectEditorPage(group: group, existingGroups: groups,
                              serviceCount: model.configs.filter { $0.group == group }.count,
                              onCancel: { route.back() }, onSave: { name in
                                  model.renameGroup(group, to: name)
                                  handoffNotice = "Project renamed"
                                  route.back()
                              })
        case .projectActions(let group):
            ProjectActionsPage(group: group,
                               serviceCount: model.configs.filter { $0.group == group }.count,
                               onBack: { route.back() },
                               onAdd: { addService(to: group) },
                               onRestart: { model.restartGroup(group); route.back() },
                               onRename: { route.editProject(group) },
                               onDelete: { route.confirmProjectDelete(group) })
        case .projectDelete(let group):
            DeleteProjectPage(group: group, serviceCount: model.configs.filter { $0.group == group }.count,
                              runningCount: model.configs.filter { $0.group == group && isRunning(model.state(for: $0)) }.count,
                              onCancel: { route.back() }, onDelete: {
                                  model.deleteGroup(group)
                                  handoffNotice = "\(group) removed"
                                  route.back()
                              })
        case .output(let id):
            if let config = model.configs.first(where: { $0.id == id }) {
                ServiceOutputPage(config: config, model: model, onBack: { route.back() }, onPin: { route.openTerminals?(config.id) })
            } else {
                PortkeeperGlassButton(action: { route.back() }) { Text("Back to services") }
            }
        case .stopListener(let listener):
            StopListenerPage(listener: listener, managedServiceName: model.managedService(for: listener)?.name,
                             otherPorts: Array(Set(model.listeners.filter {
                                 $0.pid == listener.pid && $0.port != listener.port
                             }.map(\.port))).sorted(),
                             onCancel: { route.back() }, onStop: {
                                 Task {
                                     let result = await model.stopListener(listener)
                                     route.showStopResult(result)
                                 }
                             })
        case .stopResult(let message):
            StopResultPage(message: message, onBack: { route.back() })
        case .importReview:
            if let project = route.pendingImport {
                ProjectImportPreview(project: project, listeners: model.listeners,
                                     onCancel: { route.back() }, onImport: { start in
                                         model.importProject(project, startImmediately: start)
                                         tab = .services
                                         route.selectedTab = .services
                                         route.back()
                                     })
            }
        case .pasteJSON:
            PasteProjectPage(onBack: { route.page = .handoff }, onReview: route.reviewImport)
        case .handoff:
            HandoffActionsPage(onBack: { route.back() }, onCopy: { copyBrief(); route.back() },
                               onSave: saveBrief, onPaste: { route.page = .pasteJSON }, onImport: chooseManifest)
        case .settings:
            SettingsActionsPage(model: model, onBack: { route.back() },
                                onQuit: { NSApplication.shared.terminate(nil) })
        }
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            header
            if !embedded {
                Button { route.openTerminals?(nil) } label: {
                    HStack {
                        Label("Active terminals", systemImage: "sidebar.right")
                        Spacer()
                        Text("Pin all active").foregroundStyle(PortkeeperStyle.cyan)
                    }.font(.system(size: 11, weight: .medium, design: .monospaced)).padding(10)
                }
                .buttonStyle(.plain)
                .background(PortkeeperStyle.well, in: RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, 18).padding(.vertical, 10)
            }
            tabBar
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            if let panelError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(PortkeeperStyle.coral)
                    Text(panelError).font(.system(size: 10, design: .monospaced)).lineLimit(2)
                    Spacer()
                    Button { self.panelError = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }
                .padding(10)
                .background(PortkeeperStyle.well, in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 17)
                .padding(.bottom, 10)
            }

            if tab == .services, let focused = route.focusedConfigID,
               let config = model.configs.first(where: { $0.id == focused }) {
                focusedIssue(config)
            }

            if tab == .services { servicesView }
            else { portsView }

            footer
        }
        .frame(width: 400, height: embedded ? nil : 590)
    }

    private func focusedIssue(_ config: ServiceConfig) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PortkeeperStyle.coral)
            VStack(alignment: .leading, spacing: 3) {
                Text(config.name).font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(route.issueMessage ?? model.activeIssues[config.id]?.message ?? "Review this service's status and output.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(PortkeeperStyle.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 3)
            Button { copyIssuePrompt(config, observedIssue: route.issueMessage) } label: {
                Image(systemName: "sparkles")
            }
            .buttonStyle(.plain)
            .foregroundStyle(PortkeeperStyle.coral)
            .help("Copy an AI prompt about this issue")
        }
        .padding(10)
        .background(PortkeeperStyle.well.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(PortkeeperStyle.coral.opacity(0.45), lineWidth: 1))
        .padding(.horizontal, 17)
        .padding(.bottom, 10)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 27, weight: .light, design: .monospaced))
                .foregroundStyle(PortkeeperStyle.green)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("portkeeper_").font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PortkeeperStyle.ivory)
                HStack(spacing: 5) {
                    Text("\(model.listeners.count) listening ports · \(runningCount) managed")
                        .foregroundStyle(PortkeeperStyle.muted)
                    if issueCount > 0 {
                        Text("· \(issueCount) issue\(issueCount == 1 ? "" : "s")")
                            .foregroundStyle(PortkeeperStyle.coral)
                    }
                }
                .font(.system(size: 10, design: .monospaced))
            }
            Spacer()
            PortkeeperGlassButton(action: { model.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(width: 20, height: 20)
            }
            .help("Scan ports now")
        }
        .padding(.horizontal, 18)
        .padding(.top, 17)
        .padding(.bottom, 14)
        .background(Color.black)
        .overlay(alignment: .bottom) { PortkeeperStyle.line.opacity(0.55).frame(height: 1) }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(PanelTab.allCases, id: \.self) { choice in
                Button { tab = choice; route.selectedTab = choice } label: {
                    HStack(spacing: 7) {
                        Image(systemName: choice == .services ? "square.stack" : "network")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Text(choice.rawValue).font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(tab == choice ? PortkeeperStyle.ivory : PortkeeperStyle.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(tab == choice ? PortkeeperStyle.raised.opacity(0.40) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .modifier(PortkeeperChrome(radius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 13)
    }

    private var runningCount: Int {
        model.configs.filter { isRunning(model.state(for: $0)) }.count
    }

    private var issueCount: Int { model.activeIssues.count + (model.scanError == nil ? 0 : 1) }

    private var servicesView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 15) {
                if model.configs.isEmpty {
                    emptyServices
                } else {
                    ForEach(groups, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(PortkeeperStyle.coral)
                                Text(group.uppercased())
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .tracking(1.3)
                                    .foregroundStyle(PortkeeperStyle.muted)
                                Spacer()
                                Button { route.showProjectActions(group) } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(PortkeeperStyle.muted)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("Edit or delete \(group)")
                                Button { model.restartGroup(group) } label: {
                                    Image(systemName: "arrow.clockwise").frame(width: 20, height: 20)
                                }.buttonStyle(.plain)
                                    .disabled(model.isRestartingGroup(group))
                                    .help("Restart all services in \(group)")
                                Button { model.toggleGroup(group) } label: {
                                    Image(systemName: model.isGroupRunning(group) ? "stop.fill" : "play.fill")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(PortkeeperStyle.ivory)
                                        .frame(width: 20, height: 20)
                                        .portkeeperChrome(radius: 7)
                                }
                                .buttonStyle(.plain)
                                .help(model.isGroupRunning(group) ? "Stop all in \(group)" : "Start all in \(group)")
                            }
                            .padding(.horizontal, 8)
                            ForEach(model.configs.filter { $0.group == group }) { config in
                                serviceRow(config)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
    }

    private var groups: [String] {
        return Array(Set(model.configs.map(\.group))).sorted {
            if $0 == model.recentProject { return true }
            if $1 == model.recentProject { return false }
            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func serviceRow(_ config: ServiceConfig) -> some View {
        let state = model.state(for: config)
        return HStack(spacing: 10) {
            Circle().fill(statusColor(state)).frame(width: 8, height: 8)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(config.name).font(.system(size: 13, weight: .semibold, design: .monospaced)).lineLimit(1)
                        .foregroundStyle(PortkeeperStyle.ivory)
                }
                Text(subtitle(config, state: state))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isOccupied(state) ? PortkeeperStyle.coral : PortkeeperStyle.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Button { route.activateTerminal?(config.id) } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(.plain).foregroundStyle(PortkeeperStyle.green)
                .frame(width: 22, height: 26).help("Open terminal workspace")
            if case .failed = state {
                Button { openOutput(config) } label: { Image(systemName: "terminal") }
                    .buttonStyle(.plain).foregroundStyle(PortkeeperStyle.cyan)
                    .frame(width: 22, height: 26).help("View startup output")
            }
            if case .unhealthy = state {
                Button { openOutput(config) } label: { Image(systemName: "terminal") }
                    .buttonStyle(.plain).foregroundStyle(PortkeeperStyle.cyan)
                    .frame(width: 22, height: 26).help("View startup output")
            }
            if isProblem(state) {
                Button { copyIssuePrompt(config) } label: { Image(systemName: "sparkles") }
                    .buttonStyle(.plain).foregroundStyle(PortkeeperStyle.coral)
                    .frame(width: 22, height: 26).help("Copy an AI prompt about this service issue")
            }
            if config.port != nil || !config.url.isEmpty {
                Button { model.open(config) } label: { Image(systemName: "arrow.up.right") }
                    .buttonStyle(.plain).foregroundStyle(PortkeeperStyle.cyan)
                    .frame(width: 22, height: 26).help("Open local address")
            }
            Button { route.showServiceActions(config) } label: {
                Image(systemName: "ellipsis").foregroundStyle(PortkeeperStyle.muted).frame(width: 22, height: 26)
            }
            .buttonStyle(.plain)
            .help("Edit, view output, or remove \(config.name)")
            .frame(width: 24)
            Button { model.toggle(config) } label: {
                Image(systemName: isRunning(state) ? "stop.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(isRunning(state) ? PortkeeperStyle.coral : PortkeeperStyle.ivory)
                    .frame(width: 28, height: 28)
                    .portkeeperChrome(radius: 7)
            }
            .buttonStyle(.plain)
            .disabled(isOccupied(state))
            .help(isOccupied(state) ? "Port already belongs to another process" : isRunning(state) ? "Stop service" : "Start service")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(PortkeeperStyle.well.opacity(0.70), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(PortkeeperStyle.line.opacity(0.42), lineWidth: 1))
    }

    private func subtitle(_ config: ServiceConfig, state: ServiceState) -> String {
        switch state {
        case .failed(let error): return error
        case .unhealthy(let error): return error
        case .occupied(let listener): return "IN USE · \(config.port ?? 0) · \(listener.process) (PID \(listener.pid))"
        case .starting: return "Starting · \(config.port.map(String.init) ?? "tunnel")"
        case .running: return "Running · \(config.port.map(String.init) ?? "tunnel")"
        case .stopped: return config.port.map { ":\($0) · \(config.command)" } ?? config.command
        }
    }

    private func statusColor(_ state: ServiceState) -> Color {
        switch state {
        case .running: return PortkeeperStyle.cyan
        case .starting: return PortkeeperStyle.ivory
        case .occupied, .unhealthy, .failed: return PortkeeperStyle.coral
        case .stopped: return PortkeeperStyle.muted.opacity(0.5)
        }
    }
    private func isRunning(_ state: ServiceState) -> Bool {
        if case .running = state { return true }
        if case .unhealthy = state { return true }
        if case .starting = state { return true }
        return false
    }
    private func isOccupied(_ state: ServiceState) -> Bool {
        if case .occupied = state { return true }; return false
    }
    private func isProblem(_ state: ServiceState) -> Bool {
        switch state {
        case .failed, .unhealthy, .occupied: return true
        default: return false
        }
    }

    private var emptyServices: some View {
        VStack(spacing: 11) {
            Image(systemName: "terminal").font(.system(size: 25, weight: .light, design: .monospaced)).foregroundStyle(PortkeeperStyle.cyan)
            Text("No services yet").font(.system(size: 15, weight: .medium, design: .monospaced))
            Text("Add a command to start it from the menu bar.")
                .font(.caption).foregroundStyle(PortkeeperStyle.muted)
            PortkeeperGlassButton(prominent: true, action: { addService() }) { Text("Add service") }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 110)
    }

    private var portsView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(PortkeeperStyle.muted)
                TextField("Filter by port or process", text: $search).textFieldStyle(.plain)
                    .foregroundStyle(PortkeeperStyle.ivory)
            }
            .padding(10)
            .background(PortkeeperStyle.well.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(PortkeeperStyle.line.opacity(0.65), lineWidth: 1))
            .padding(.horizontal, 17)
            .padding(.bottom, 10)
            if let error = model.scanError {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(PortkeeperStyle.coral)
                    Text(error).font(.caption).foregroundStyle(PortkeeperStyle.ivory).lineLimit(2)
                    Spacer()
                    Button { copyScanPrompt(error) } label: { Image(systemName: "sparkles") }
                        .buttonStyle(.plain).foregroundStyle(PortkeeperStyle.coral)
                        .frame(width: 25, height: 25).help("Copy an AI prompt about this port-scan error")
                }
                .padding(.horizontal, 18).padding(.bottom, 10)
            }
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(filteredListeners) { listener in
                        HStack(spacing: 9) {
                            Circle().fill(PortkeeperStyle.cyan).frame(width: 6, height: 6)
                            Text(String(listener.port)).font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PortkeeperStyle.cyan)
                                .frame(width: 58, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(listener.process).font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(PortkeeperStyle.ivory).lineLimit(1)
                                Text("\(listener.address) · PID \(String(listener.pid))").font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(PortkeeperStyle.muted).lineLimit(1)
                            }
                            Spacer()
                            Button { copyExplanationPrompt(listener) } label: {
                                Image(systemName: "doc.on.doc").frame(width: 23, height: 23)
                            }
                            .buttonStyle(.plain).foregroundStyle(PortkeeperStyle.cyan)
                            .help("Copy a prompt to explain this listener in Codex or Cursor")
                            Button { confirmStop(listener) } label: {
                                Image(systemName: "stop.circle").frame(width: 23, height: 23)
                            }
                            .buttonStyle(.plain).foregroundStyle(PortkeeperStyle.coral)
                            .help("Stop \(listener.process) on port \(String(listener.port))")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(PortkeeperStyle.well.opacity(0.70), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(PortkeeperStyle.line.opacity(0.36), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 15)
            }
        }
    }

    private var filteredListeners: [Listener] {
        guard !search.isEmpty else { return model.listeners }
        return model.listeners.filter { "\($0.port)".contains(search) || $0.process.localizedCaseInsensitiveContains(search) || $0.address.localizedCaseInsensitiveContains(search) }
    }

    private func confirmStop(_ listener: Listener) {
        route.confirmStop(listener)
    }

    private var footer: some View {
        HStack {
            PortkeeperGlassButton(prominent: true, action: { addService() }) {
                Label("Add service", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
            }
            Button { route.showHandoff() } label: {
                Label("Project handoff", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(PortkeeperStyle.cyan)
            }
            .buttonStyle(.plain)
            .fixedSize()
            Spacer()
            if let notice = handoffNotice ?? model.importStatus {
                Text(notice).font(.system(size: 10, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted)
                    .lineLimit(1)
            }
            Button { route.showSettings() } label: {
                Image(systemName: "gearshape").foregroundStyle(PortkeeperStyle.muted)
            }
            .buttonStyle(.plain)
            .help("Portkeeper settings and quit")
            .frame(width: 20)
        }
        .padding(.horizontal, 17).padding(.vertical, 12)
        .background(Color.black)
        .overlay(alignment: .top) { PortkeeperStyle.line.opacity(0.55).frame(height: 1) }
    }

    private func addService() {
        addService(to: "My services")
    }

    private func addService(to group: String) {
        editService(ServiceConfig(name: "", group: group, directory: "", command: "", port: nil, url: ""))
    }

    private func editService(_ config: ServiceConfig) {
        route.showEditor(config)
    }

    private func reviewProject(_ project: ImportedProject) {
        route.reviewImport(project)
    }

    private func openOutput(_ config: ServiceConfig) {
        if embedded { route.openTerminals?(config.id) }
        else { route.showOutput(config.id) }
    }

    private func copyIssuePrompt(_ config: ServiceConfig, observedIssue: String? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.issuePrompt(for: config, observedIssue: observedIssue), forType: .string)
        handoffNotice = "\(config.name) AI prompt copied"
    }

    private func copyScanPrompt(_ error: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PortkeeperModel.scanIssuePrompt(error), forType: .string)
        handoffNotice = "Port scan AI prompt copied"
    }

    private func brief() -> String? {
        guard let url = Bundle.main.url(forResource: "Portkeeper-setup", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func copyBrief() {
        guard let markdown = brief() else {
            panelError = "The setup brief is missing from the app."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        handoffNotice = "Markdown copied"
    }

    private func copyExplanationPrompt(_ listener: Listener) {
        let prompt = model.explanationPrompt(for: listener)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        handoffNotice = "Port \(listener.port) prompt copied"
    }

    private func saveBrief() {
        guard let markdown = brief() else {
            panelError = "The setup brief is missing from the app."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Portkeeper-setup.md"
        if panel.runModal() == .OK, let url = panel.url {
            do { try markdown.write(to: url, atomically: true, encoding: .utf8); handoffNotice = "Markdown saved" }
            catch { panelError = "Could not save brief: \(error.localizedDescription)" }
        }
    }

    private func chooseManifest() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.message = "Choose the portkeeper.json created in your project"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                reviewProject(try ImportedProject.load(from: url))
                PortkeeperAlerts.shared.menuBar?.openPanel()
            }
            catch { panelError = "Could not import project: \(error.localizedDescription)" }
        }
    }
}

private struct ProjectImportPreview: View {
    let project: ImportedProject
    let listeners: [Listener]
    let onCancel: () -> Void
    let onImport: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import \(project.name)").font(.system(size: 20, weight: .semibold, design: .monospaced))
                    Text("Review the commands Portkeeper will be able to run.")
                        .font(.caption).foregroundStyle(PortkeeperStyle.muted)
                }
                Spacer()
                Text("\(project.services.count) service\(project.services.count == 1 ? "" : "s")")
                    .font(.caption.weight(.medium)).foregroundStyle(PortkeeperStyle.cyan)
            }
            ScrollView {
                VStack(spacing: 9) {
                    ForEach(Array(project.services.enumerated()), id: \.element.id) { index, service in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 7) {
                                Text("\(index + 1)").font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .frame(width: 19, height: 19)
                                    .background(PortkeeperStyle.well, in: Circle())
                                Text(service.name).font(.system(size: 13, weight: .semibold, design: .monospaced))
                                Spacer()
                                if let port = service.port {
                                    if let owner = listeners.first(where: { $0.port == port }) {
                                        Text(":\(String(port)) in use · \(owner.process)").foregroundStyle(PortkeeperStyle.coral)
                                    } else { Text(":\(String(port))").foregroundStyle(PortkeeperStyle.cyan) }
                                } else { Text("No port").foregroundStyle(PortkeeperStyle.muted) }
                            }
                            .font(.system(size: 11, design: .monospaced))
                            Text(service.command).font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                            Text(service.directory).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(PortkeeperStyle.muted).textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                        .background(PortkeeperStyle.well.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(PortkeeperStyle.line.opacity(0.45), lineWidth: 1))
                    }
                }
            }
            Text("Matching names in this group are updated. Occupied ports are skipped when starting; other processes are never stopped.")
                .font(.caption).foregroundStyle(PortkeeperStyle.muted)
            HStack {
                PortkeeperGlassButton(action: onCancel) { Text("Cancel") }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                PortkeeperGlassButton(action: { onImport(false) }) { Text("Import only") }
                PortkeeperGlassButton(prominent: true, action: { onImport(true) }) { Text("Import & Start") }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(19)
        .frame(width: 560, height: 510)
        .foregroundStyle(PortkeeperStyle.ivory)
        .tint(PortkeeperStyle.coral)
        .preferredColorScheme(.dark)
    }
}

private struct ServiceEditor: View {
    @State var config: ServiceConfig
    let isNew: Bool
    let onCancel: () -> Void
    let onSave: (ServiceConfig) -> Void
    @State private var portText: String

    init(config: ServiceConfig, onCancel: @escaping () -> Void, onSave: @escaping (ServiceConfig) -> Void) {
        _config = State(initialValue: config)
        isNew = config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.onCancel = onCancel
        self.onSave = onSave
        _portText = State(initialValue: config.port.map(String.init) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isNew ? "Add service" : "Edit service")
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    Text("A command runs in its project folder until you stop it.")
                        .font(.caption).foregroundStyle(PortkeeperStyle.muted)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 12) {
                field("Name") { input("Service name", text: $config.name) }
                field("Group") { input("My project", text: $config.group) }
                field("Project folder") {
                    HStack {
                        input("~/Sites/my-project", text: $config.directory)
                        Button("Browse…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            if panel.runModal() == .OK, let path = panel.url?.path { config.directory = path }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                field("Command") { input("Foreground start command", text: $config.command) }
                HStack(alignment: .top, spacing: 12) {
                    field("Expected port") { input("Optional", text: $portText) }
                    field("Open URL") { input("Optional", text: $config.url) }
                }
            }
            Text("The port is used to flag conflicts. Leave it blank for tunnels or tasks without a local listener.")
                .font(.caption).foregroundStyle(PortkeeperStyle.muted)
            HStack {
                Spacer()
                PortkeeperGlassButton(action: onCancel) { Text("Cancel") }
                    .keyboardShortcut(.cancelAction)
                PortkeeperGlassButton(prominent: true, action: save) { Text("Save") }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(22)
        .frame(width: 460, height: 510)
        .foregroundStyle(PortkeeperStyle.ivory)
        .tint(PortkeeperStyle.coral)
        .preferredColorScheme(.dark)
    }

    private func save() {
        config.name = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        config.group = config.group.trimmingCharacters(in: .whitespacesAndNewlines)
        config.directory = config.directory.trimmingCharacters(in: .whitespacesAndNewlines)
        config.command = config.command.trimmingCharacters(in: .whitespacesAndNewlines)
        config.port = Int(portText)
        onSave(config)
    }

    private func input(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(PortkeeperStyle.well.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(PortkeeperStyle.line.opacity(0.78), lineWidth: 1))
    }

    private var valid: Bool {
        !config.name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !config.group.trimmingCharacters(in: .whitespaces).isEmpty &&
        !config.directory.trimmingCharacters(in: .whitespaces).isEmpty &&
        !config.command.trimmingCharacters(in: .whitespaces).isEmpty &&
        (portText.isEmpty || (Int(portText).map { (1...65535).contains($0) } ?? false))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
