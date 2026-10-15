import AppKit
import Combine
import QuartzCore
import SwiftUI

struct NotchGeometry {
    let screen: CGRect
    let visible: CGRect
    let housingWidth: CGFloat
    let topHeight: CGFloat

    init(screen: CGRect, visible: CGRect, left: CGRect?, right: CGRect?, topInset: CGFloat) {
        self.screen = screen
        self.visible = visible
        housingWidth = left.flatMap { lhs in right.map { max(0, $0.minX - lhs.maxX) } } ?? 150
        topHeight = max(28, topInset)
    }
    init(_ screen: NSScreen) {
        self.init(screen: screen.frame, visible: screen.visibleFrame,
                  left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea,
                  topInset: screen.safeAreaInsets.top)
    }
    func notchFrame(page: CGSize?, expanded: Bool) -> CGRect {
        let width = expanded ? min(screen.width - 24, (page?.width ?? 400) + 24) : housingWidth + 112
        let height = expanded ? min(screen.height - 24, (page?.height ?? 590) + topHeight + 42) : topHeight + 6
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
    }
    func drawerFrame(expanded: Bool) -> CGRect {
        let size = expanded ? CGSize(width: min(640, visible.width - 32), height: min(780, visible.height - 32)) : CGSize(width: 30, height: 100)
        return CGRect(x: screen.maxX - size.width, y: visible.midY - size.height / 2, width: size.width, height: size.height)
    }
}

@MainActor final class EdgePanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        refreshMascots(in: contentView)
    }
    override func orderFrontRegardless() {
        let wasVisible = isVisible
        super.orderFrontRegardless()
        if !wasVisible { refreshMascots(in: contentView) }
    }
    private func refreshMascots(in view: NSView?) {
        guard let view else { return }
        (view as? PortyNativeView)?.refreshVisibility()
        for child in view.subviews { refreshMascots(in: child) }
    }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { makeKey() }
        super.sendEvent(event)
    }
    init(title: String) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.title = title
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }
}

@MainActor final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var drawerExpanded = false
    @Published var pinned = false
    @Published var portyMood: PortyMood = .idle
    @Published var activeServiceCount = 0
    @Published var housingWidth: CGFloat = 150
    @Published var topHeight: CGFloat = 28
}

@MainActor final class NotchPanelController {
    let state = NotchState()
    let notch = EdgePanel(title: "Portkeeper · Notch")
    let drawer = EdgePanel(title: "Portkeeper · Active terminals")
    private let model: PortkeeperModel
    private let route: PortkeeperPanelRoute
    private let terminals: TerminalWorkspaceController
    private var observations: [AnyCancellable] = []
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var timer: Timer?
    private var outsideNotch: Date?
    private var outsideDrawer: Date?
    private var notchSuppressed = false
    private var drawerSuppressed = false
    private var pointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var geometry: NotchGeometry?
    private var notchSurface: LiquidSurfaceView!
    private var drawerSurface: LiquidSurfaceView!
    private var accessibilityObserver: NSObjectProtocol?

    init(model: PortkeeperModel, route: PortkeeperPanelRoute, terminals: TerminalWorkspaceController) {
        self.model = model; self.route = route; self.terminals = terminals
        notchSurface = LiquidSurfaceView(edge: .notch,
            expanded: NotchRoot(model: model, route: route, state: state,
                close: { [weak self] in self?.collapseNotch() },
                toggle: { [weak self] in self?.showNotch(focus: true) }),
            compact: NotchBeacon(state: state,
                open: { [weak self] in self?.showNotch(focus: true) }))
        drawerSurface = LiquidSurfaceView(edge: .drawer,
            expanded: TerminalDrawer(model: model, workspace: terminals.state,
                openWorkspace: { [weak self] in self?.collapseDrawer(); self?.terminals.show() },
                close: { [weak self] in self?.collapseDrawer() }),
            compact: DrawerHandle(model: model, workspace: terminals.state, state: state,
                open: { [weak self] in self?.expandDrawer() }))
        notch.contentView = notchSurface
        drawer.contentView = drawerSurface
        notchSurface.onPointerEntered = { [weak self] in
            guard let self, !self.state.expanded, !self.notchSuppressed else { return }
            self.showNotch(focus: false)
        }
        drawerSurface.onPointerEntered = { [weak self] in
            guard let self, !self.state.drawerExpanded, !self.drawerSuppressed else { return }
            self.expandDrawer()
        }
        drawerSurface.onSettled = { [weak self] in
            guard let self else { return }
            if self.terminals.state.activeTerminals.isEmpty && !self.state.drawerExpanded { self.drawer.orderOut(nil) }
        }
        notch.onEscape = { [weak self] in self?.collapseNotch() }
        drawer.onEscape = { [weak self] in self?.collapseDrawer() }
        observations.append(route.$page.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout(animated: true) }
        })
        observations.append(terminals.state.$activeTerminals.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout(animated: true) }
        })
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout(animated: false) }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout(animated: false) }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout(animated: false); self?.updatePortyStatus() }
        }
        let motionEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: motionEvents) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: motionEvents) { [weak self] event in
            MainActor.assumeIsolated { self?.tick() }
            return event
        }
        notch.acceptsMouseMovedEvents = true; drawer.acceptsMouseMovedEvents = true
        observations.append(model.objectWillChange
            .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updatePortyStatus() }
            })
        observations.append(model.$shareWithNotchwork.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout(animated: false) }
        })
        layout(animated: false)
        updatePortyStatus()
    }

    func shutdown() {
        timer?.invalidate(); timer = nil
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        pointerMonitor = nil; localPointerMonitor = nil
        observations.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        notchSurface.stopMotion(); drawerSurface.stopMotion()
        notch.orderOut(nil); drawer.orderOut(nil)
    }
    func toggleNotch() {
        if state.expanded { collapseNotch() } else { showNotch(focus: true) }
    }
    func showNotch(focus: Bool = true) {
        state.expanded = true
        outsideNotch = nil
        layout(animated: true)
        if focus { notch.makeKeyAndOrderFront(nil) }
        tick()
    }
    func collapseNotch() {
        state.expanded = false; state.pinned = false
        notchSuppressed = true
        notch.makeFirstResponder(nil); notch.resignKey()
        layout(animated: true)
    }
    func activateTerminal(_ id: UUID) {
        terminals.state.activeTerminals.insert(id)
        expandDrawer()
    }
    func expandDrawer() {
        state.drawerExpanded = true
        outsideDrawer = nil
        layout(animated: true)
        tick()
    }
    func collapseDrawer() {
        state.drawerExpanded = false
        drawerSuppressed = true
        drawer.makeFirstResponder(nil); drawer.resignKey()
        layout(animated: true)
    }
    private func layout(animated: Bool) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let geometry = NotchGeometry(screen)
        self.geometry = geometry
        if state.housingWidth != geometry.housingWidth { state.housingWidth = geometry.housingWidth }
        if state.topHeight != geometry.topHeight { state.topHeight = geometry.topHeight }
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        notchSurface.move(compact: geometry.notchFrame(page: nil, expanded: false),
                          expanded: geometry.notchFrame(page: route.page.size, expanded: true),
                          open: state.expanded, animated: animate)
        if model.shareWithNotchwork && !state.expanded { notch.orderOut(nil) }
        else { notch.orderFrontRegardless() }
        if model.shareWithNotchwork && !state.drawerExpanded {
            drawerSurface.stopMotion(); drawer.orderOut(nil); return
        }
        if !terminals.state.activeTerminals.isEmpty || state.drawerExpanded || drawer.isVisible {
            drawerSurface.move(compact: geometry.drawerFrame(expanded: false),
                               expanded: geometry.drawerFrame(expanded: true),
                               open: state.drawerExpanded, animated: animate)
            if !terminals.state.activeTerminals.isEmpty || state.drawerExpanded || drawerSurface.isAnimating {
                drawer.orderFrontRegardless()
            } else { drawer.orderOut(nil) }
        }
    }
    private func editing(_ panel: NSPanel) -> Bool {
        guard panel.isKeyWindow else { return false }
        return (panel.firstResponder as? NSTextView)?.isEditable == true
    }
    private func tick() {
        let now = Date()
        // Modal pickers and open menus keep their owning surface stable.
        guard NSApp.modalWindow == nil, !NSApp.windows.contains(where: { $0.isVisible && $0.className.contains("Menu") }) else { return }
        let point = NSEvent.mouseLocation
        notchSurface.updatePointerPassThrough(); drawerSurface.updatePointerPassThrough()
        let overNotch = notchSurface.containsScreenPoint(point)
        if !overNotch { notchSuppressed = false }
        if overNotch {
            outsideNotch = nil
            if !state.expanded && !notchSuppressed { showNotch(focus: false) }
        } else if state.expanded && !state.pinned && route.page == .dashboard && !editing(notch) {
            if outsideNotch == nil { outsideNotch = now }
            if now.timeIntervalSince(outsideNotch!) >= 0.6 { collapseNotch() }
        }
        let overDrawer = drawer.isVisible && drawerSurface.containsScreenPoint(point)
        if !overDrawer { drawerSuppressed = false }
        if overDrawer {
            outsideDrawer = nil
            if !state.drawerExpanded && !drawerSuppressed { expandDrawer() }
        } else if state.drawerExpanded && !editing(drawer) {
            if outsideDrawer == nil { outsideDrawer = now }
            if now.timeIntervalSince(outsideDrawer!) >= 0.7 { collapseDrawer() }
        }
        var deadlines: [Date] = []
        if state.expanded, !state.pinned, route.page == .dashboard, !editing(notch), let outsideNotch {
            deadlines.append(outsideNotch.addingTimeInterval(0.6))
        }
        if state.drawerExpanded, !editing(drawer), let outsideDrawer { deadlines.append(outsideDrawer.addingTimeInterval(0.7)) }
        if let next = deadlines.min(), timer == nil {
            timer = Timer(timeInterval: max(0.01, next.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.timer = nil; self?.tick() }
            }
            RunLoop.main.add(timer!, forMode: .common)
        } else if deadlines.isEmpty { timer?.invalidate(); timer = nil }
    }
    private func updatePortyStatus() {
        let statuses = model.configs.map { model.state(for: $0) }
        let mood = PortyMood.resolve(statuses, hasIssue: !model.activeIssues.isEmpty || model.scanError != nil)
        let count = statuses.filter(\.terminalActive).count
        if state.portyMood != mood { state.portyMood = mood }
        if state.activeServiceCount != count { state.activeServiceCount = count }
    }
}

private struct NotchBeacon: View {
    @ObservedObject var state: NotchState
    var compact = true
    let open: () -> Void
    private var count: Int { state.activeServiceCount }
    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                Text(String(format: "%02d", count))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 48, height: state.topHeight)
            }.accessibilityLabel("Open Portkeeper, \(count) active services")
            Color.clear.frame(width: state.housingWidth).accessibilityHidden(true)
            Button(action: open) {
                PortyFace(mood: state.portyMood, active: compact != state.expanded)
                    .frame(width: 30, height: 24)
                    .frame(width: 48, height: state.topHeight)
            }.accessibilityLabel("Open Portkeeper. " + state.portyMood.description)
                .help(state.portyMood.description)
        }
        .buttonStyle(.plain).foregroundStyle(PortkeeperStyle.green)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }
}

private struct NotchRoot: View {
    @ObservedObject var model: PortkeeperModel
    @ObservedObject var route: PortkeeperPanelRoute
    @ObservedObject var state: NotchState
    let close: () -> Void
    let toggle: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            NotchBeacon(state: state, compact: false, open: toggle).frame(height: state.topHeight)
            HStack {
                Text(model.hasAttentionIssue ? "! ATTENTION REQUIRED" : "› LOCAL SERVICES")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                Spacer()
                Button { state.pinned.toggle() } label: { Image(systemName: state.pinned ? "pin.fill" : "pin") }
                    .help(state.pinned ? "Unpin notch panel" : "Keep notch panel open")
                    .accessibilityLabel(state.pinned ? "Unpin notch panel" : "Keep notch panel open")
                Button(action: close) { Image(systemName: "xmark") }.help("Collapse notch panel")
                    .accessibilityLabel("Collapse notch panel")
            }.buttonStyle(.plain).foregroundStyle(PortkeeperStyle.green)
                .padding(.horizontal, 22).frame(height: 30)
            ScrollView([.vertical, .horizontal]) {
                PortkeeperPanel(model: model, route: route)
            }.scrollIndicators(.hidden)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }
}

private struct DrawerHandle: View {
    @ObservedObject var model: PortkeeperModel
    @ObservedObject var workspace: TerminalWorkspaceState
    @ObservedObject var state: NotchState
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(spacing: 9) {
                Image(systemName: "chevron.left")
                PortyFace(mood: state.portyMood, active: !state.drawerExpanded && !workspace.activeTerminals.isEmpty)
                    .frame(width: 24, height: 19)
                Text("\(workspace.activeTerminals.count)")
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(PortkeeperStyle.green)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.buttonStyle(.plain)
            .accessibilityLabel("Show \(workspace.activeTerminals.count) active terminals")
    }
}

extension PortkeeperModel {
    var hasAttentionIssue: Bool {
        !activeIssues.isEmpty || scanError != nil || configs.contains {
            switch state(for: $0) { case .failed, .unhealthy: return true; default: return false }
        }
    }
}
