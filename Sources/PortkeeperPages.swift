import AppKit
import SwiftUI

struct ProjectActionsPage: View {
    let group: String
    let serviceCount: Int
    let onBack: () -> Void
    let onAdd: () -> Void
    let onRestart: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            pageHeading(group, detail: "\(serviceCount) service\(serviceCount == 1 ? "" : "s") in this project")
            actionRow("Add service", icon: "plus", action: onAdd)
            actionRow("Restart project", icon: "arrow.clockwise", action: onRestart)
            actionRow("Rename project", icon: "pencil", action: onRename)
            actionRow("Delete project", icon: "trash", destructive: true, action: onDelete)
            Spacer(minLength: 0)
            PortkeeperGlassButton(action: onBack) { Text("Back to services") }
        }
        .padding(22)
        .frame(width: 420, height: 350)
    }
}

struct ServiceActionsPage: View {
    let config: ServiceConfig
    let onBack: () -> Void
    let onEdit: () -> Void
    let onOutput: () -> Void
    let onRestart: () -> Void
    let onActivate: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            pageHeading(config.name, detail: config.group)
            actionRow("Edit service", icon: "pencil", action: onEdit)
            actionRow("View output", icon: "terminal", action: onOutput)
            actionRow("Restart service", icon: "arrow.clockwise", action: onRestart)
            actionRow("Make terminal active", icon: "sidebar.right", action: onActivate)
            actionRow("Remove service", icon: "trash", destructive: true, action: onRemove)
            Spacer(minLength: 0)
            PortkeeperGlassButton(action: onBack) { Text("Back to services") }
        }
        .padding(22)
        .frame(width: 420, height: 400)
    }
}

struct HandoffActionsPage: View {
    let onBack: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onPaste: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            pageHeading("Project handoff", detail: "Give your coding platform the brief, then import its project JSON.")
            actionRow("Copy Markdown brief", icon: "doc.on.doc", action: onCopy)
            actionRow("Save Markdown brief…", icon: "square.and.arrow.down", action: onSave)
            actionRow("Paste project JSON", icon: "curlybraces", action: onPaste)
            actionRow("Import project JSON…", icon: "square.and.arrow.up", action: onImport)
            Spacer(minLength: 0)
            PortkeeperGlassButton(action: onBack) { Text("Back to services") }
        }
        .padding(22)
        .frame(width: 420, height: 350)
    }
}

struct SettingsActionsPage: View {
    @ObservedObject var model: PortkeeperModel
    let onBack: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            pageHeading("Portkeeper", detail: "A harbour view of the local services you manage.")
            Text(model.notchworkStatus).font(.system(size: 11, design: .monospaced))
            Button("Open Notchwork / Retry") {
                Task {
                    do { try await model.presentNotchwork() }
                    catch { model.notchworkStatus = error.localizedDescription }
                }
            }
            Text("Quitting asks Portkeeper-managed services to stop.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(PortkeeperStyle.muted)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PortkeeperStyle.well, in: RoundedRectangle(cornerRadius: 6))
            Spacer(minLength: 0)
            HStack {
                PortkeeperGlassButton(action: onBack) { Text("Back") }
                Spacer()
                PortkeeperGlassButton(action: onQuit) { Text("Quit Portkeeper") }
            }
        }
        .padding(22)
        .frame(width: 420, height: 290)
    }
}

private func actionRow(_ title: String, icon: String, destructive: Bool = false,
                       action: @escaping () -> Void) -> some View {
    PortkeeperGlassButton(action: action) {
        HStack(spacing: 11) {
            Image(systemName: icon).frame(width: 18)
                .foregroundStyle(destructive ? PortkeeperStyle.coral : PortkeeperStyle.ivory)
            Text(title).font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(destructive ? PortkeeperStyle.coral : PortkeeperStyle.ivory)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(PortkeeperStyle.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .frame(height: 32)
    }
}

struct ProjectEditorPage: View {
    let group: String
    let existingGroups: [String]
    let serviceCount: Int
    let onCancel: () -> Void
    let onSave: (String) -> Void
    @State private var name: String

    init(group: String, existingGroups: [String], serviceCount: Int,
         onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.group = group
        self.existingGroups = existingGroups
        self.serviceCount = serviceCount
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: group)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            pageHeading("Rename project", detail: "This updates the group for \(serviceCount) service\(serviceCount == 1 ? "" : "s").")
            VStack(alignment: .leading, spacing: 6) {
                Text("Project name").font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(PortkeeperStyle.muted)
                TextField("Project name", text: $name)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(PortkeeperStyle.well, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(PortkeeperStyle.line, lineWidth: 1))
            }
            if !valid {
                Text("Use a unique name of up to 80 characters.")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(PortkeeperStyle.coral)
            }
            Spacer()
            HStack {
                PortkeeperGlassButton(action: onCancel) { Text("Cancel") }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                PortkeeperGlassButton(prominent: true, action: { onSave(trimmed) }) { Text("Save project") }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
            }
        }
        .padding(22)
        .frame(width: 420, height: 290)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool {
        !trimmed.isEmpty && trimmed.count <= 80 && !existingGroups.contains {
            $0 != group && $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }
}

struct DeleteProjectPage: View {
    let group: String
    let serviceCount: Int
    let runningCount: Int
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeading("Delete project?", detail: "\(group) contains \(serviceCount) service\(serviceCount == 1 ? "" : "s").")
            VStack(alignment: .leading, spacing: 6) {
                Text(group).font(.system(size: 15, weight: .semibold, design: .monospaced))
                Text("Its saved services and Portkeeper logs will be removed.")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted)
                if runningCount > 0 {
                    Text("\(runningCount) running service\(runningCount == 1 ? "" : "s") will be asked to stop.")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(PortkeeperStyle.coral)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(PortkeeperStyle.well, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(PortkeeperStyle.line, lineWidth: 1))
            Spacer()
            HStack {
                PortkeeperGlassButton(action: onCancel) { Text("Cancel") }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                PortkeeperGlassButton(prominent: true, action: onDelete) { Text("Delete project") }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420, height: 290)
    }
}

struct DeleteServicePage: View {
    let config: ServiceConfig
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeading("Remove service?", detail: "Remove \(config.name) from \(config.group).")
            VStack(alignment: .leading, spacing: 6) {
                Text(config.name).font(.system(size: 15, weight: .semibold, design: .monospaced))
                Text(config.command).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PortkeeperStyle.muted).lineLimit(2)
                Text("A running process will be asked to stop. Its saved output will be removed.")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(PortkeeperStyle.well, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(PortkeeperStyle.line, lineWidth: 1))
            Spacer()
            HStack {
                PortkeeperGlassButton(action: onCancel) { Text("Cancel") }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                PortkeeperGlassButton(prominent: true, action: onDelete) { Text("Remove service") }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420, height: 290)
    }
}

struct ServiceOutputPage: View {
    let config: ServiceConfig
    @ObservedObject var model: PortkeeperModel
    let onBack: () -> Void
    let onPin: () -> Void
    @State private var copied = false
    @State private var fontSize = 11.0
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onBack) { Image(systemName: "chevron.left") }.help("Back to services")
                Text(config.name).font(.system(size: 17, weight: .semibold, design: .monospaced)).lineLimit(1)
                Spacer()
                Button(action: onPin) { Label("Pin", systemImage: "pin") }
                Button(copied ? "Copied" : "Copy AI prompt") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(PortkeeperModel.troubleshootingPrompt(for: config, output: model.logs[config.id] ?? ""), forType: .string)
                    copied = true
                }
            }
            TerminalLogView(output: model.logs[config.id] ?? "", fontSize: fontSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Recent output · AI prompts redact secrets").font(.system(size: 10, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted)
                Spacer()
                Button("A−") { fontSize = max(9, fontSize - 1) }.help("Smaller terminal text")
                Button("A+") { fontSize = min(18, fontSize + 1) }.help("Larger terminal text")
            }
        }.padding(19).frame(width: 620, height: 480)
    }
}

struct StopListenerPage: View {
    let listener: Listener
    let managedServiceName: String?
    let otherPorts: [Int]
    let onCancel: () -> Void
    let onStop: () -> Void
    @State private var stopping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            pageHeading("Stop listener?", detail: managedServiceName.map {
                "This stops the Portkeeper service \($0) and its child processes."
            } ?? "Portkeeper will ask this process to quit gracefully.")
            VStack(alignment: .leading, spacing: 6) {
                Text("\(listener.process) · PID \(listener.pid)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Text(listener.address).font(.system(size: 11, design: .monospaced))
                if !otherPorts.isEmpty {
                    Text("It also listens on \(otherPorts.map { ":\($0)" }.joined(separator: ", ")).")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(PortkeeperStyle.well, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(PortkeeperStyle.line, lineWidth: 1))
            Spacer()
            HStack {
                PortkeeperGlassButton(action: onCancel) { Text("Cancel") }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                PortkeeperGlassButton(prominent: true, action: {
                    stopping = true
                    onStop()
                }) { Text(stopping ? "Stopping…" : "Stop process") }
                    .keyboardShortcut(.defaultAction)
                    .disabled(stopping)
            }
        }
        .padding(22)
        .frame(width: 420, height: 290)
    }
}

struct StopResultPage: View {
    let message: String
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            pageHeading("Port action", detail: message)
            Spacer()
            HStack {
                Spacer()
                PortkeeperGlassButton(prominent: true, action: onBack) { Text("Back to ports") }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420, height: 210)
    }
}

private func pageHeading(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 20, weight: .semibold, design: .monospaced))
        Text(detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
