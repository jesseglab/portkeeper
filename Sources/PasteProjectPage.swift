import AppKit
import SwiftUI

struct PasteProjectPage: View {
    let onBack: () -> Void
    let onReview: (ImportedProject) -> Void
    @State private var json = ""
    @State private var baseDirectory: URL?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("paste project.json").font(.system(size: 19, weight: .semibold, design: .monospaced))
                    Text("Paste the handoff, then review its services and commands.")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(PortkeeperStyle.muted)
                }
                Spacer()
                Button("Paste") {
                    if let text = NSPasteboard.general.string(forType: .string) { json = text; error = nil }
                }.buttonStyle(TerminalButtonStyle())
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $json)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(8)
                    .accessibilityLabel("Project JSON")
                if json.isEmpty {
                    Text("{\n  \"version\": 1,\n  \"project\": \"My project\",\n  \"services\": […]\n}")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(PortkeeperStyle.muted).padding(14).allowsHitTesting(false)
                }
            }
            .background(Color.black)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(PortkeeperStyle.line))
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BASE FOLDER · for relative paths").font(.system(size: 9, design: .monospaced))
                    Text(baseDirectory?.path ?? "Not needed for absolute paths")
                        .font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                }.foregroundStyle(PortkeeperStyle.muted)
                Spacer()
                Button("Choose…") {
                    let picker = NSOpenPanel()
                    picker.canChooseDirectories = true; picker.canChooseFiles = false
                    picker.allowsMultipleSelection = false
                    if picker.runModal() == .OK { baseDirectory = picker.url; error = nil }
                }.buttonStyle(TerminalButtonStyle())
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PortkeeperStyle.green).lineLimit(3)
            }
            HStack {
                Button("Back", action: onBack).buttonStyle(TerminalButtonStyle())
                Spacer()
                Button("Review project") {
                    do { onReview(try ImportedProject.paste(json, baseDirectory: baseDirectory)) }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(TerminalButtonStyle(prominent: true))
                    .disabled(json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22).frame(width: 560, height: 510)
        .onChange(of: json) { _, _ in error = nil }
    }
}
