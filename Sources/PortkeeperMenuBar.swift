import AppKit
import Combine
import SwiftUI

enum PortkeeperPage: Hashable {
    case dashboard
    case serviceEditor(ServiceConfig)
    case serviceActions(ServiceConfig)
    case serviceDelete(ServiceConfig)
    case projectActions(String)
    case projectEditor(String)
    case projectDelete(String)
    case output(UUID)
    case stopListener(Listener)
    case stopResult(String)
    case importReview
    case handoff
    case pasteJSON
    case settings

    var size: NSSize {
        switch self {
        case .pasteJSON: return NSSize(width: 560, height: 510)
        case .serviceActions: return NSSize(width: 420, height: 400)
        case .projectActions, .handoff: return NSSize(width: 420, height: 350)
        case .dashboard: return NSSize(width: 400, height: 590)
        case .serviceEditor: return NSSize(width: 460, height: 510)
        case .serviceDelete, .projectEditor,
             .projectDelete, .stopListener, .settings:
            return NSSize(width: 420, height: 290)
        case .stopResult: return NSSize(width: 420, height: 210)
        case .output: return NSSize(width: 620, height: 480)
        case .importReview: return NSSize(width: 560, height: 510)
        }
    }
}

@MainActor final class PortkeeperPanelRoute: ObservableObject {
    @Published var revision = 0
    @Published var page: PortkeeperPage = .dashboard
    var activateTerminal: ((UUID) -> Void)?
    var openTerminals: ((UUID?) -> Void)?
    var selectedTab: PanelTab = .services
    var focusedConfigID: UUID?
    var issueMessage: String?
    var pendingImport: ImportedProject?

    func showEditor(_ config: ServiceConfig) { page = .serviceEditor(config) }
    func showServiceActions(_ config: ServiceConfig) { page = .serviceActions(config) }
    func confirmServiceDelete(_ config: ServiceConfig) { page = .serviceDelete(config) }
    func showProjectActions(_ group: String) { page = .projectActions(group) }
    func editProject(_ group: String) { page = .projectEditor(group) }
    func confirmProjectDelete(_ group: String) { page = .projectDelete(group) }
    func showOutput(_ id: UUID) { page = .output(id) }
    func confirmStop(_ listener: Listener) { page = .stopListener(listener) }
    func showStopResult(_ message: String) { page = .stopResult(message) }
    func reviewImport(_ project: ImportedProject) {
        pendingImport = project
        page = .importReview
    }
    func showHandoff() { page = .handoff }
    func showSettings() { page = .settings }
    func back() { page = .dashboard }

    func showService(_ id: UUID, message: String?) {
        page = .dashboard
        selectedTab = .services
        focusedConfigID = id
        issueMessage = message
        revision += 1
    }

    func showPorts() {
        page = .dashboard
        selectedTab = .ports
        focusedConfigID = nil
        issueMessage = nil
        revision += 1
    }

    func clearFocus() {
        focusedConfigID = nil
        issueMessage = nil
        revision += 1
    }
}

@MainActor final class PortkeeperDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: PortkeeperMenuBar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = PortkeeperModel()
        let menuBar = PortkeeperMenuBar(model: model)
        self.menuBar = menuBar
        model.openNotchworkControls = { [weak menuBar] in menuBar?.openWorkspace() }
        model.openNotchworkPage = { [weak menuBar] page, identity in menuBar?.openPage(page, identity: identity) }
        PortkeeperAlerts.shared.menuBar = menuBar
        model.startNotchwork()
    }
}

@MainActor final class PortkeeperMenuBar: NSObject {
    private let model: PortkeeperModel
    private let terminals: TerminalWorkspaceController
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var observation: AnyCancellable?

    init(model: PortkeeperModel) {
        self.model = model
        self.terminals = TerminalWorkspaceController(model: model)
        model.notchworkPages.terminalState = terminals.state
        model.notchworkPages.detachTerminal = { [weak terminals] in terminals?.openDetached($0) }
        super.init()
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Portkeeper")
        item.button?.toolTip = "Open Portkeeper in Notchwork"
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.item.button?.image = NSImage(systemSymbolName: self.model.hasAttentionIssue ? "exclamationmark.triangle" : "terminal", accessibilityDescription: "Portkeeper")
            }
        }
    }
    @objc private func togglePanel() { openPanel() }
    func openServiceIssue(_ id: UUID, message: String?) {
        model.notchworkPages.dashboard()
        model.notchworkNotice = message ?? model.configs.first(where: { $0.id == id }).map { "Review \($0.name) status and output." } ?? "Review service status and output."
        openPanel()
    }
    func openScanIssue() { model.notchworkPages.dashboard(ports: true); openPanel() }
    func openWorkspace() { terminals.show() }
    func openPage(_ page: String, identity: String) { terminals.showPage(page, identity: identity) }
    func openPanel() {
        Task {
            do { try await model.presentNotchwork() }
            catch {
                model.notchworkStatus = error.localizedDescription
                terminals.showSettings()
            }
        }
    }
}
