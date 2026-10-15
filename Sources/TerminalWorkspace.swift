import AppKit
import Combine
import SwiftUI

@MainActor final class TerminalWorkspaceController: NSObject, NSWindowDelegate {
    let state: TerminalWorkspaceState
    private let model: PortkeeperModel
    private let route = PortkeeperPanelRoute()
    private var window: NSWindow?
    private var detached: [UUID: NSWindow] = [:]
    private var observation: AnyCancellable?
    private var levelObservation: AnyCancellable?
    private var pageObservation: AnyCancellable?

    init(model: PortkeeperModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.state = TerminalWorkspaceState(defaults: defaults)
        super.init()
        state.reconcile(Set(model.configs.map(\.id)))
        state.assignColors(model.configs)
        route.activateTerminal = { [weak self] id in self?.state.activeTerminals.insert(id) }
        route.openTerminals = { [weak self] id in self?.show(id: id) }
        observation = model.$configs.dropFirst().sink { [weak self] configs in
            DispatchQueue.main.async {
                guard let self else { return }
                let ids = Set(configs.map(\.id))
                self.state.reconcile(ids)
                self.state.assignColors(configs)
                for id in Array(self.detached.keys) where !ids.contains(id) { self.detached[id]?.close() }
                if self.state.project != "All projects", !configs.contains(where: { $0.group == self.state.project }) { self.state.project = "All projects" }
            }
        }
        levelObservation = state.$keepOnTop.sink { [weak self] on in
            self?.window?.level = on ? .floating : .normal
            self?.detached.values.forEach { $0.level = on ? .floating : .normal }
        }
        pageObservation = route.$page.sink { [weak self] page in
            DispatchQueue.main.async { self?.window?.contentMinSize = NSSize(width: page.size.width + 520, height: max(560, page.size.height)) }
        }
    }
    func show(id: UUID? = nil) {
        if let id { state.pin([id]); state.preferences.collapsed.remove(id) }
        else { pinActive() }
        state.search = ""; state.status = .all; state.project = "All projects"
        if window == nil {
            let view = TerminalWorkspaceView(model: model, route: route, workspace: state, pinActive: { [weak self] in self?.pinActive() }, popOut: { [weak self] in self?.openDetached($0) })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Portkeeper · Terminal workspace"
            window.contentViewController = NSHostingController(rootView: view)
            window.contentMinSize = NSSize(width: 920, height: 590)
            window.isReleasedWhenClosed = false
            window.level = state.keepOnTop ? .floating : .normal
            window.setFrameAutosaveName("PortkeeperTerminalWorkspace")
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func pinActive() { state.pin(model.configs.filter { model.state(for: $0).terminalActive }.map(\.id)) }
    func openDetached(_ config: ServiceConfig) {
        if let existing = detached[config.id] { existing.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 320), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "\(config.name) · \(config.group)"
        window.contentViewController = NSHostingController(rootView: DetachedTerminalView(id: config.id, model: model, workspace: state))
        window.contentMinSize = NSSize(width: 380, height: 150)
        window.isReleasedWhenClosed = false
        window.level = state.keepOnTop ? .floating : .normal
        window.delegate = self
        if let parent = self.window, let screen = parent.screen {
            let visible = screen.visibleFrame
            let x = min(parent.frame.maxX + 10, visible.maxX - window.frame.width)
            let y = max(visible.minY, parent.frame.maxY - window.frame.height - CGFloat(detached.count % 4) * 38)
            window.setFrameOrigin(NSPoint(x: max(visible.minX, x), y: y))
        } else { window.center() }
        detached[config.id] = window
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        for id in Array(detached.keys) where detached[id] === closing { detached[id] = nil }
    }
}

private struct DetachedTerminalView: View {
    let id: UUID
    @ObservedObject var model: PortkeeperModel
    @ObservedObject var workspace: TerminalWorkspaceState
    var body: some View {
        Group {
            if let config = model.configs.first(where: { $0.id == id }) {
                TerminalCard(config: config, model: model, workspace: workspace, detached: true)
            } else { Text("Service removed") }
        }
        .padding(8).background(PortkeeperStyle.navy).foregroundStyle(PortkeeperStyle.ivory).preferredColorScheme(.dark)
    }
}

struct TerminalWorkspaceView: View {
    @ObservedObject var model: PortkeeperModel
    @ObservedObject var route: PortkeeperPanelRoute
    @ObservedObject var workspace: TerminalWorkspaceState
    let pinActive: () -> Void
    let popOut: (ServiceConfig) -> Void
    private var visible: [ServiceConfig] { workspace.visible(model.configs, state: model.state) }
    private var groups: [String] {
        switch workspace.preferences.grouping {
        case .none: return [""]
        case .project: return Array(Set(visible.map(\.group))).sorted()
        case .status: return Array(Set(visible.map { model.state(for: $0).terminalLabel })).sorted()
        }
    }
    private func members(_ group: String) -> [ServiceConfig] {
        visible.filter { config in
            switch workspace.preferences.grouping {
            case .none: return true
            case .project: return config.group == group
            case .status: return model.state(for: config).terminalLabel == group
            }
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            PortkeeperPanel(model: model, route: route, embedded: true)
            Rectangle().fill(PortkeeperStyle.line.opacity(0.5)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                header
                filters
                if workspace.preferences.pinned.isEmpty {
                    empty("Your terminals, together", detail: "Pin active services to watch their output here. Open any service’s terminal to pin it individually.", icon: "terminal")
                } else if visible.isEmpty {
                    empty("No matching terminals", detail: "Try another project, status, or search.", icon: "line.3.horizontal.decrease.circle")
                    Button("Clear filters") { workspace.search = ""; workspace.project = "All projects"; workspace.status = .all }
                        .padding(.horizontal, 20).padding(.bottom, 20)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(groups, id: \.self) { group in
                                if !group.isEmpty {
                                    HStack {
                                        Text(group.uppercased()).tracking(1)
                                        Text("\(members(group).count)").foregroundStyle(PortkeeperStyle.cyan)
                                        Rectangle().fill(PortkeeperStyle.line.opacity(0.4)).frame(height: 1)
                                    }
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted).padding(.top, 5)
                                }
                                ForEach(members(group)) { config in
                                    TerminalCard(config: config, model: model, workspace: workspace, popOut: { popOut(config) })
                                }
                            }
                        }.padding(16)
                    }
                }
                HStack {
                    Text("\(visible.count) shown · \(workspace.preferences.pinned.count) pinned")
                    Spacer()
                    Text("Unpinning leaves services running")
                }
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted).padding(12)
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            .background(PortkeeperStyle.navy)
        }
        .foregroundStyle(PortkeeperStyle.ivory).tint(PortkeeperStyle.cyan).preferredColorScheme(.dark)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Terminal workspace").font(.system(size: 20, weight: .semibold, design: .monospaced))
                    Text("Live output, in one place.").font(.system(size: 11, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted)
                }
                Spacer()
                Button(action: pinActive) { Label("Pin all active", systemImage: "pin.fill") }
                    .buttonStyle(.borderedProminent)
                    .help("Pin every active managed service without starting or restarting anything")
            }
            HStack(spacing: 10) {
                Picker("Size", selection: $workspace.preferences.density) {
                    ForEach(TerminalDensity.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 125).accessibilityLabel("Terminal size")
                Button { workspace.preferences.fontSize = max(9, workspace.preferences.fontSize - 1) } label: { Image(systemName: "textformat.size.smaller") }
                    .disabled(workspace.preferences.fontSize <= 9).help("Smaller terminal text").accessibilityLabel("Smaller terminal text")
                Button { workspace.preferences.fontSize = min(18, workspace.preferences.fontSize + 1) } label: { Image(systemName: "textformat.size.larger") }
                    .disabled(workspace.preferences.fontSize >= 18).help("Larger terminal text").accessibilityLabel("Larger terminal text")
                Spacer()
                Toggle("Keep on top", isOn: $workspace.keepOnTop).toggleStyle(.checkbox)
                Menu {
                    Button("Collapse all") { workspace.preferences.collapsed = Set(workspace.preferences.pinned) }
                    Button("Expand all") { workspace.preferences.collapsed = [] }
                    Divider()
                    Button("Unpin all") { workspace.preferences.pinned = []; workspace.preferences.collapsed = [] }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Workspace actions")
            }.font(.system(size: 11, design: .monospaced)).buttonStyle(.borderless)
        }.padding(18)
    }
    private var filters: some View {
        VStack(spacing: 9) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(PortkeeperStyle.muted)
                TextField("Filter terminals by name, command, or port", text: $workspace.search)
                    .textFieldStyle(.plain).accessibilityLabel("Filter terminals")
                if !workspace.search.isEmpty { Button { workspace.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear terminal search") }
            }
            HStack {
                Picker("Project", selection: $workspace.project) {
                    Text("All projects").tag("All projects")
                    ForEach(Array(Set(model.configs.map(\.group))).sorted(), id: \.self) { Text($0).tag($0) }
                }.labelsHidden().accessibilityLabel("Filter by project")
                Picker("Status", selection: $workspace.status) {
                    ForEach(TerminalStatusFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 100).accessibilityLabel("Filter by status")
                Picker("Group", selection: $workspace.preferences.grouping) {
                    ForEach(TerminalGrouping.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(width: 155)
            }
        }
        .font(.system(size: 11, design: .monospaced)).padding(.horizontal, 18).padding(.vertical, 12).background(PortkeeperStyle.well)
    }
    private func empty(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.system(size: 32, weight: .light, design: .monospaced)).foregroundStyle(PortkeeperStyle.cyan)
            Text(title).font(.system(size: 19, weight: .semibold, design: .monospaced))
            Text(detail).font(.system(size: 12, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted).fixedSize(horizontal: false, vertical: true)
            if workspace.preferences.pinned.isEmpty { Button("Pin all active", action: pinActive).buttonStyle(.bordered) }
            Spacer()
        }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
