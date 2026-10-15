import AppKit
import SwiftUI

struct TerminalDrawer: View {
    @ObservedObject var model: PortkeeperModel
    @ObservedObject var workspace: TerminalWorkspaceState
    let openWorkspace: () -> Void
    let close: () -> Void
    @State private var search = ""
    @State private var status: TerminalStatusFilter = .all
    @State private var grouping: TerminalGrouping = .project

    private var services: [ServiceConfig] {
        model.configs.filter { config in
            guard workspace.activeTerminals.contains(config.id) else { return false }
            let state = model.state(for: config)
            let matches: Bool
            switch status {
            case .all: matches = true
            case .active: matches = state.terminalActive
            case .issues: matches = state.terminalIssue
            case .stopped: matches = !state.terminalActive
            }
            return matches && (search.isEmpty || "\(config.name) \(config.group) \(config.command) \(config.port.map(String.init) ?? "")".localizedCaseInsensitiveContains(search))
        }
    }
    private func section(_ config: ServiceConfig) -> String {
        switch grouping {
        case .project: return config.group
        case .status: return model.state(for: config).terminalLabel
        case .none: return "Terminals"
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill").foregroundStyle(PortkeeperStyle.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("active terminals_").font(.system(size: 17, weight: .semibold, design: .monospaced))
                    Text("\(services.count) selected · grouped by \(grouping.rawValue.lowercased())")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted)
                }
                Spacer()
                Button(action: openWorkspace) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("Open full terminal workspace").accessibilityLabel("Open full terminal workspace")
                Button(action: close) { Image(systemName: "xmark") }
                    .help("Collapse terminal drawer").accessibilityLabel("Collapse terminal drawer")
            }.buttonStyle(.plain).padding(18)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(PortkeeperStyle.muted)
                TextField("Find service, project, command, port", text: $search).textFieldStyle(.plain)
                Menu {
                    ForEach(model.configs) { config in
                        Toggle("\(config.group) / \(config.name)", isOn: Binding(
                            get: { workspace.activeTerminals.contains(config.id) },
                            set: { if $0 { workspace.activeTerminals.insert(config.id) } else { workspace.activeTerminals.remove(config.id) } }
                        ))
                    }
                    Divider()
                    Button("Add all running") {
                        workspace.activeTerminals.formUnion(model.configs.filter { model.state(for: $0).terminalActive }.map(\.id))
                    }
                } label: { Label("Add", systemImage: "plus") }.fixedSize()
            }.font(.system(size: 11, design: .monospaced)).padding(.horizontal, 18).padding(.bottom, 12)
            HStack {
                Picker("Show", selection: $status) {
                    ForEach(TerminalStatusFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Group", selection: $grouping) {
                    ForEach(TerminalGrouping.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Spacer()
                Button("A−") { workspace.preferences.fontSize = max(9, workspace.preferences.fontSize - 1) }
                Button("A+") { workspace.preferences.fontSize = min(18, workspace.preferences.fontSize + 1) }
            }.font(.system(size: 10, design: .monospaced)).padding(.horizontal, 18).padding(.bottom, 12)
            PortkeeperStyle.line.frame(height: 1)
            if services.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No terminals in this view.").foregroundStyle(PortkeeperStyle.green)
                    Text("Use Add to select services, or clear the filters. Selecting a terminal never starts its command.")
                        .foregroundStyle(PortkeeperStyle.muted)
                    if !search.isEmpty || status != .all {
                        Button("Clear filters") { search = ""; status = .all }
                    }
                }.font(.system(size: 12, design: .monospaced)).padding(24)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(Set(services.map(section))).sorted(), id: \.self) { group in
                            HStack {
                                Text("// \(group.uppercased())").tracking(1)
                                Spacer()
                                if grouping == .project {
                                    Button("Restart project") { model.restartGroup(group) }
                                        .disabled(model.isRestartingGroup(group))
                                }
                            }.font(.system(size: 10, design: .monospaced)).foregroundStyle(PortkeeperStyle.green)
                            ForEach(services.filter { section($0) == group }) { config in
                                TerminalCard(config: config, model: model, workspace: workspace, edge: true)
                            }
                        }
                    }.padding(16)
                }
            }
            HStack {
                Circle().fill(PortkeeperStyle.green).frame(width: 5, height: 5)
                Text("LIVE OUTPUT / INPUT / ERRORS")
                Spacer()
                Text("esc to collapse")
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted).padding(14)
        }
        .background(Color.black).foregroundStyle(PortkeeperStyle.ivory)
        .tint(PortkeeperStyle.green).preferredColorScheme(.dark)
    }
}
