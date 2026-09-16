import AppKit
import Combine
import SwiftUI

enum PortkeeperPage: Equatable {
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
    case settings

    var size: NSSize {
        switch self {
        case .dashboard: return NSSize(width: 400, height: 590)
        case .serviceEditor: return NSSize(width: 460, height: 510)
        case .serviceActions, .serviceDelete, .projectActions, .projectEditor,
             .projectDelete, .stopListener, .handoff, .settings:
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
        PortkeeperAlerts.shared.menuBar = menuBar
    }
}

@MainActor final class PortkeeperMenuBar: NSObject {
    private let model: PortkeeperModel
    private let route = PortkeeperPanelRoute()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var modelObservation: AnyCancellable?
    private var pageObservation: AnyCancellable?
    private var beaconTimer: Timer?
    private var flashOn = true

    init(model: PortkeeperModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 400, height: 590)
        popover.contentViewController = NSHostingController(rootView: PortkeeperPanel(model: model, route: route))
        pageObservation = route.$page.sink { [weak self] page in
            DispatchQueue.main.async { self?.popover.contentSize = page.size }
        }
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.imageScaling = .scaleProportionallyDown
        modelObservation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshIcon() }
        }
        beaconTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIcon(advanceFlash: true) }
        }
        refreshIcon()
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil) }
        else {
            route.clearFocus()
            showPanel()
        }
    }

    func openServiceIssue(_ id: UUID, message: String?) {
        route.showService(id, message: message)
        showPanel()
    }

    func openScanIssue() {
        route.showPorts()
        showPanel()
    }

    func openPanel() { showPanel() }

    private func showPanel() {
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func refreshIcon(advanceFlash: Bool = false) {
        let hasIssue = !model.activeIssues.isEmpty || model.scanError != nil || model.configs.contains {
            switch model.state(for: $0) {
            case .failed, .unhealthy: return true
            default: return false
            }
        }
        let active = model.configs.contains {
            switch model.state(for: $0) {
            case .running, .starting, .unhealthy: return true
            default: return false
            }
        }
        if hasIssue && advanceFlash { flashOn.toggle() }
        if !hasIssue { flashOn = true }
        let lit = hasIssue ? flashOn : active
        item.button?.image = LighthouseStatusIcon.image(lit: lit, alert: hasIssue)
        item.button?.toolTip = hasIssue ? "Portkeeper · issue needs attention" :
            active ? "Portkeeper · services active" : "Portkeeper · no managed services active"
    }
}

private enum LighthouseStatusIcon {
    static func image(lit: Bool, alert: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let context = NSGraphicsContext.current!.cgContext
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / 64, y: rect.height / 64)

            if lit {
                let amber = NSColor(calibratedRed: 0.94, green: 0.65, blue: 0.30, alpha: 1)
                let beam = NSBezierPath()
                beam.move(to: NSPoint(x: 36, y: 45))
                beam.line(to: NSPoint(x: 54, y: 40))
                beam.line(to: NSPoint(x: 54, y: 51))
                beam.close()
                amber.withAlphaComponent(alert ? 0.65 : 0.38).setFill()
                beam.fill()
            }

            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 16, y: 5, width: 32, height: 8), xRadius: 4, yRadius: 4).fill()
            let tower = NSBezierPath()
            tower.move(to: NSPoint(x: 22, y: 12))
            tower.line(to: NSPoint(x: 42, y: 12))
            tower.line(to: NSPoint(x: 38, y: 38))
            tower.line(to: NSPoint(x: 26, y: 38))
            tower.close()
            tower.fill()
            NSBezierPath(roundedRect: NSRect(x: 22, y: 36, width: 20, height: 5), xRadius: 2, yRadius: 2).fill()
            NSBezierPath(roundedRect: NSRect(x: 24, y: 40, width: 16, height: 10), xRadius: 2, yRadius: 2).fill()
            NSBezierPath(roundedRect: NSRect(x: 19, y: 48, width: 26, height: 7), xRadius: 4, yRadius: 4).fill()
            NSBezierPath(ovalIn: NSRect(x: 22, y: 51, width: 20, height: 8)).fill()
            NSBezierPath(ovalIn: NSRect(x: 29, y: 58, width: 6, height: 6)).fill()

            // The lantern stays dark when idle and during the off beat of an alert.
            context.setBlendMode(.clear)
            NSBezierPath(roundedRect: NSRect(x: 28, y: 42, width: 8, height: 6), xRadius: 1, yRadius: 1).fill()
            NSBezierPath(roundedRect: NSRect(x: 29, y: 13, width: 6, height: 8), xRadius: 3, yRadius: 3).fill()
            context.setBlendMode(.normal)
            if lit {
                NSColor(calibratedRed: 1, green: 0.74, blue: 0.38, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 29, y: 43, width: 6, height: 4), xRadius: 1, yRadius: 1).fill()
            }
            context.restoreGState()
            return true
        }
        image.isTemplate = false
        return image
    }
}
