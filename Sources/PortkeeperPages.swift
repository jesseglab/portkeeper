import AppKit
import SwiftUI

struct ProjectActionsPage: View {
    let group: String
    let serviceCount: Int
    let onBack: () -> Void
    let onAdd: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            pageHeading(group, detail: "\(serviceCount) service\(serviceCount == 1 ? "" : "s") in this project")
            actionRow("Add service", icon: "plus", action: onAdd)
            actionRow("Rename project", icon: "pencil", action: onRename)
            actionRow("Delete project", icon: "trash", destructive: true, action: onDelete)
            Spacer(minLength: 0)
            PortkeeperGlassButton(action: onBack) { Text("Back to services") }
        }
        .padding(22)
        .frame(width: 420, height: 290)
    }
}

struct ServiceActionsPage: View {
    let config: ServiceConfig
    let onBack: () -> Void
    let onEdit: () -> Void
    let onOutput: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            pageHeading(config.name, detail: config.group)
            actionRow("Edit service", icon: "pencil", action: onEdit)
            actionRow("View output", icon: "terminal", action: onOutput)
            actionRow("Remove service", icon: "trash", destructive: true, action: onRemove)
            Spacer(minLength: 0)
            PortkeeperGlassButton(action: onBack) { Text("Back to services") }
        }
        .padding(22)
        .frame(width: 420, height: 290)
    }
}

struct HandoffActionsPage: View {
    let onBack: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            pageHeading("Project handoff", detail: "Give your coding platform the brief, then import its project JSON.")
            actionRow("Copy Markdown brief", icon: "doc.on.doc", action: onCopy)
            actionRow("Save Markdown brief…", icon: "square.and.arrow.down", action: onSave)
            actionRow("Import project JSON…", icon: "square.and.arrow.up", action: onImport)
            Spacer(minLength: 0)
            PortkeeperGlassButton(action: onBack) { Text("Back to services") }
        }
        .padding(22)
        .frame(width: 420, height: 290)
    }
}

struct SettingsActionsPage: View {
    let onBack: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            pageHeading("Portkeeper", detail: "A harbour view of the local services you manage.")
            Text("Quitting asks Portkeeper-managed services to stop.")
                .font(.system(size: 11))
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
            Text(title).font(.system(size: 12, weight: .medium))
                .foregroundStyle(destructive ? PortkeeperStyle.coral : PortkeeperStyle.ivory)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
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
                Text("Project name").font(.system(size: 11, weight: .medium))
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
                    .font(.system(size: 10)).foregroundStyle(PortkeeperStyle.coral)
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
                Text(group).font(.system(size: 15, weight: .semibold))
                Text("Its saved services and Portkeeper logs will be removed.")
                    .font(.system(size: 11)).foregroundStyle(PortkeeperStyle.muted)
                if runningCount > 0 {
                    Text("\(runningCount) running service\(runningCount == 1 ? "" : "s") will be asked to stop.")
                        .font(.system(size: 11)).foregroundStyle(PortkeeperStyle.coral)
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
                Text(config.name).font(.system(size: 15, weight: .semibold))
                Text(config.command).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PortkeeperStyle.muted).lineLimit(2)
                Text("A running process will be asked to stop. Its saved output will be removed.")
                    .font(.system(size: 11)).foregroundStyle(PortkeeperStyle.muted)
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
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                PortkeeperGlassButton(action: onBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: 16, height: 16)
                }
                Text("Output · \(config.name)").font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                PortkeeperGlassButton(action: copyPrompt) {
                    Label(copied ? "Copied" : "Copy AI prompt", systemImage: copied ? "checkmark" : "sparkles")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            ScrollView {
                Text(PortkeeperModel.readableOutput(model.logs[config.id] ?? "No output yet."))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
            }
            .background(PortkeeperStyle.well, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(PortkeeperStyle.line.opacity(0.7), lineWidth: 1))
            HStack {
                Text("Recent output · secrets are redacted in AI prompts")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(PortkeeperStyle.muted)
                Spacer()
                PortkeeperGlassButton(action: onBack) { Text("Back to services") }
            }
        }
        .padding(19)
        .frame(width: 620, height: 480)
    }

    private func copyPrompt() {
        let prompt = PortkeeperModel.troubleshootingPrompt(for: config, output: model.logs[config.id] ?? "")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copied = true
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
                    .font(.system(size: 14, weight: .semibold))
                Text(listener.address).font(.system(size: 11, design: .monospaced))
                if !otherPorts.isEmpty {
                    Text("It also listens on \(otherPorts.map { ":\($0)" }.joined(separator: ", ")).")
                        .font(.system(size: 11)).foregroundStyle(PortkeeperStyle.muted)
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
        Text(title).font(.system(size: 20, weight: .semibold))
        Text(detail).font(.system(size: 11)).foregroundStyle(PortkeeperStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
