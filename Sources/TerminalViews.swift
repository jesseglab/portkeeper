import AppKit
import SwiftUI

struct TerminalLogView: View {
    let output: String
    var fontSize: Double = 11
    @State private var query = ""
    @State private var level: TerminalLogFilter = .all
    @State private var follow = true
    @State private var wrap = true
    @State private var copied = false

    private var filtered: String { TerminalOutput.filtered(output, query: query, level: level) }
    var body: some View {
        let filtered = self.filtered
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(PortkeeperStyle.muted)
                TextField("Find in output", text: $query).textFieldStyle(.plain)
                    .accessibilityLabel("Find in output")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.help("Clear output search")
                }
                Picker("Lines", selection: $level) { ForEach(TerminalLogFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .labelsHidden().frame(width: 96).accessibilityLabel("Output level")
                Button { wrap.toggle() } label: { Image(systemName: "text.word.spacing") }
                    .foregroundStyle(wrap ? PortkeeperStyle.cyan : PortkeeperStyle.muted)
                    .help(wrap ? "Disable line wrapping" : "Wrap long lines")
                    .accessibilityLabel(wrap ? "Disable line wrapping" : "Wrap long lines")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(TerminalOutput.plain(filtered), forType: .string)
                    copied = true
                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .help("Copy visible output").accessibilityLabel("Copy visible output")
            }
            .font(.system(size: 11, design: .monospaced)).buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 7)
            .background(PortkeeperStyle.well)
            ZStack {
                TerminalTextView(text: filtered, fontSize: fontSize, wrap: wrap, follow: $follow)
                if filtered.isEmpty {
                    Text(output.isEmpty ? "Waiting for output…" : "No lines match these filters")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12)
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 6) {
                Text(level == .all && query.isEmpty ? "RECENT OUTPUT" : "FILTERED OUTPUT")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                Spacer()
                Button { follow.toggle() } label: {
                    Label(follow ? "Following" : "Follow latest", systemImage: follow ? "arrow.down.to.line" : "pause.fill")
                }
                .buttonStyle(.plain).font(.system(size: 10, design: .monospaced)).foregroundStyle(follow ? PortkeeperStyle.cyan : PortkeeperStyle.coral)
                .help("Pause following to inspect earlier output")
            }
            .foregroundStyle(PortkeeperStyle.muted).padding(.horizontal, 10).padding(.vertical, 5)
        }
        .background(Color.black)
        .onChange(of: output) { _, _ in copied = false }
        .onChange(of: query) { _, _ in copied = false }
        .onChange(of: level) { _, _ in copied = false }
    }
}

private final class TerminalScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        if event.scrollingDeltaY > 0 { onUserScroll?() }
    }
}

struct TerminalTextView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    let wrap: Bool
    @Binding var follow: Bool
    final class Coordinator {
        var lastText: String?
        var fontSize: Double = 0
        var wrap = true
        var wasFollowing = true
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = TerminalScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = NSTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isRichText = true
        view.isAutomaticLinkDetectionEnabled = false
        view.textContainerInset = NSSize(width: 10, height: 10)
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.setAccessibilityLabel("Terminal output")
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        (scroll as? TerminalScrollView)?.onUserScroll = { follow = false }
        let cache = context.coordinator
        let changed = cache.lastText != text || cache.fontSize != fontSize || cache.wrap != wrap
        if changed {
            let origin = scroll.contentView.bounds.origin
            let selection = view.selectedRange()
            view.isHorizontallyResizable = !wrap
            view.autoresizingMask = wrap ? [.width] : []
            view.textContainer?.widthTracksTextView = wrap
            view.textContainer?.containerSize = NSSize(width: wrap ? max(1, scroll.contentSize.width - 20) : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            if wrap { view.setFrameSize(NSSize(width: scroll.contentSize.width, height: view.frame.height)) }
            view.textStorage?.setAttributedString(TerminalOutput.attributed(text, fontSize: fontSize))
            let length = view.string.utf16.count
            let location = min(selection.location, length)
            view.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
            view.layoutManager?.ensureLayout(for: view.textContainer!)
            if !wrap, let rect = view.layoutManager?.usedRect(for: view.textContainer!) {
                view.setFrameSize(NSSize(width: max(scroll.contentSize.width, rect.width + 24), height: max(scroll.contentSize.height, rect.height + 24)))
            }
            if !follow { scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView) }
            cache.lastText = text; cache.fontSize = fontSize; cache.wrap = wrap
        }
        if follow && (changed || !cache.wasFollowing) { view.scrollToEndOfDocument(nil) }
        cache.wasFollowing = follow
    }
}

struct TerminalCard: View {
    let config: ServiceConfig
    @ObservedObject var model: PortkeeperModel
    @ObservedObject var workspace: TerminalWorkspaceState
    var popOut: (() -> Void)?
    var detached = false
    var edge = false
    @State private var copiedPrompt = false
    private var color: Color { edge ? PortkeeperStyle.green : TerminalPalette.colors[workspace.colorIndex(config.id)] }
    private var collapsed: Bool { !detached && workspace.preferences.collapsed.contains(config.id) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if !detached {
                    Button { workspace.toggleCollapsed(config.id) } label: { Image(systemName: collapsed ? "chevron.right" : "chevron.down") }
                        .help(collapsed ? "Expand terminal" : "Collapse terminal")
                        .accessibilityLabel(collapsed ? "Expand \(config.name)" : "Collapse \(config.name)")
                }
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name).font(.system(size: 12, weight: .semibold, design: .monospaced)).lineLimit(1)
                    Text("\(config.group)\(config.port.map { " · :\($0)" } ?? "")")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(model.state(for: config).terminalLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(model.state(for: config).terminalIssue ? PortkeeperStyle.coral : color)
                Menu {
                    Button(workspace.activeTerminals.contains(config.id) ? "Remove from edge drawer" : "Make terminal active") {
                        if !workspace.activeTerminals.insert(config.id).inserted { workspace.activeTerminals.remove(config.id) }
                    }
                    Button("Restart service") { model.restart(config) }.disabled(model.restarting.contains(config.id))
                    Button(model.state(for: config).terminalActive ? "Stop service" : "Start service") { model.toggle(config) }
                    Picker("Color", selection: Binding(get: { workspace.colorIndex(config.id) }, set: { workspace.preferences.colors[config.id] = $0 })) {
                        ForEach(TerminalPalette.names.indices, id: \.self) { Text(TerminalPalette.names[$0]).tag($0) }
                    }
                    Button(copiedPrompt ? "AI prompt copied" : "Copy AI prompt") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.issuePrompt(for: config), forType: .string)
                        copiedPrompt = true
                    }
                    if !detached {
                        Divider()
                        Button("Move up") { workspace.move(config.id, by: -1) }
                        Button("Move down") { workspace.move(config.id, by: 1) }
                        if let popOut { Button("Open in separate window", action: popOut) }
                        Divider()
                        Button("Unpin terminal") { workspace.unpin(config.id) }
                    }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    .help("Terminal color, order, and actions").accessibilityLabel("Actions for \(config.name)")
                if !detached && !edge {
                    Button { workspace.unpin(config.id) } label: { Image(systemName: "pin.slash") }
                        .help("Unpin terminal; service keeps running").accessibilityLabel("Unpin \(config.name)")
                }
            }
            .buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 9)
            .background(color.opacity(0.10))
            if !collapsed {
                TerminalLogView(output: model.logs[config.id] ?? "", fontSize: workspace.preferences.fontSize)
                    .frame(maxHeight: .infinity)
                TerminalInputView(config: config, model: model)
            }
        }
        .frame(height: detached ? nil : collapsed ? 48 : workspace.preferences.density.height)
        .background(PortkeeperStyle.navy)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.45), lineWidth: 1))
    }
}

struct TerminalInputView: View {
    let config: ServiceConfig
    @ObservedObject var model: PortkeeperModel
    @State private var input = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("stdin >").foregroundStyle(PortkeeperStyle.green)
                TextField(model.acceptsInput(config.id) ? "Send a line to this service" : "Start service to send input", text: $input)
                    .textFieldStyle(.plain).onSubmit(send)
                    .disabled(!model.acceptsInput(config.id))
                    .accessibilityLabel("Input for \(config.name)")
                Button(action: send) { Image(systemName: "return") }
                    .buttonStyle(.plain).disabled(!model.acceptsInput(config.id) || input.isEmpty)
                    .help("Send input to \(config.name)")
            }
            if let error { Text(error).foregroundStyle(PortkeeperStyle.green) }
        }
        .font(.system(size: 10, design: .monospaced)).padding(10)
        .background(Color.black)
        .overlay(alignment: .top) { PortkeeperStyle.line.frame(height: 1) }
    }
    private func send() {
        guard !input.isEmpty else { return }
        error = model.sendInput(input, to: config.id)
        if error == nil { input = "" }
    }
}
