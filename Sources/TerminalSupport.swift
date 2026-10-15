import AppKit
import Combine
import SwiftUI

enum TerminalDensity: String, CaseIterable, Codable {
    case compact = "Compact", comfortable = "Comfortable", large = "Large"
    var height: CGFloat { switch self { case .compact: return 180; case .comfortable: return 290; case .large: return 440 } }
}
enum TerminalGrouping: String, CaseIterable, Codable { case project = "Project", status = "Status", none = "None" }
enum TerminalStatusFilter: String, CaseIterable { case all = "All", active = "Active", issues = "Issues", stopped = "Inactive" }
enum TerminalLogFilter: String, CaseIterable { case all = "All lines", errors = "Errors", warnings = "Warnings", inputs = "Inputs" }

extension ServiceState {
    var terminalActive: Bool {
        switch self { case .starting, .running, .unhealthy: return true; default: return false }
    }
    var terminalIssue: Bool {
        switch self { case .failed, .unhealthy, .occupied: return true; default: return false }
    }
    var terminalLabel: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .running: return "Running"
        case .unhealthy: return "Unhealthy"
        case .occupied: return "Port occupied"
        case .failed: return "Failed"
        }
    }
}

struct TerminalPreferences: Codable {
    var pinned: [UUID] = []
    var collapsed: Set<UUID> = []
    var colors: [UUID: Int] = [:]
    var density: TerminalDensity = .comfortable
    var grouping: TerminalGrouping = .project
    var fontSize: Double = 11
}

@MainActor final class TerminalWorkspaceState: ObservableObject {
    @Published var preferences: TerminalPreferences { didSet { save() } }
    @Published var activeTerminals: Set<UUID> { didSet { defaults.set(activeTerminals.map(\.uuidString), forKey: "edgeTerminals.v1") } }
    @Published var search = ""
    @Published var status: TerminalStatusFilter = .all
    @Published var project = "All projects"
    @Published var keepOnTop = false
    private let defaults: UserDefaults
    private let key = "terminalWorkspace.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        activeTerminals = Set((defaults.stringArray(forKey: "edgeTerminals.v1") ?? []).compactMap(UUID.init(uuidString:)))
        preferences = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(TerminalPreferences.self, from: $0) } ?? TerminalPreferences()
        preferences.pinned = preferences.pinned.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        preferences.fontSize = min(18, max(9, preferences.fontSize))
    }
    private func save() { if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: key) } }
    func pin(_ ids: [UUID]) { for id in ids where !preferences.pinned.contains(id) { preferences.pinned.append(id) } }
    func unpin(_ id: UUID) { preferences.pinned.removeAll { $0 == id }; preferences.collapsed.remove(id) }
    func reconcile(_ ids: Set<UUID>) {
        activeTerminals.formIntersection(ids)
        preferences.pinned.removeAll { !ids.contains($0) }
        preferences.collapsed.formIntersection(ids)
        preferences.colors = preferences.colors.filter { ids.contains($0.key) }
    }
    func toggleCollapsed(_ id: UUID) {
        if !preferences.collapsed.insert(id).inserted { preferences.collapsed.remove(id) }
    }
    func move(_ id: UUID, by offset: Int) {
        guard let index = preferences.pinned.firstIndex(of: id), preferences.pinned.indices.contains(index + offset) else { return }
        preferences.pinned.swapAt(index, index + offset)
    }
    func colorIndex(_ id: UUID) -> Int {
        if let choice = preferences.colors[id] { return abs(choice % TerminalPalette.colors.count) }
        // Assign unused palette entries first; saved choices stay stable across launches and reordering.
        let used = Set(preferences.colors.values)
        return TerminalPalette.colors.indices.first { !used.contains($0) } ?? Int(id.uuid.0) % TerminalPalette.colors.count
    }
    func assignColors(_ configs: [ServiceConfig]) {
        for config in configs where preferences.colors[config.id] == nil { preferences.colors[config.id] = colorIndex(config.id) }
    }
    func visible(_ configs: [ServiceConfig], state: (ServiceConfig) -> ServiceState) -> [ServiceConfig] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return preferences.pinned.compactMap { id in configs.first { $0.id == id } }.filter { config in
            let current = state(config)
            let matchesStatus: Bool
            switch status {
            case .all: matchesStatus = true
            case .active: matchesStatus = current.terminalActive
            case .issues: matchesStatus = current.terminalIssue
            case .stopped: matchesStatus = !current.terminalActive
            }
            return matchesStatus && (project == "All projects" || project == config.group) &&
                (query.isEmpty || "\(config.name) \(config.group) \(config.command) \(config.port.map(String.init) ?? "")".localizedCaseInsensitiveContains(query))
        }
    }
}

enum TerminalPalette {
    static let names = ["Seafoam", "Sky", "Amber", "Orchid", "Rose", "Lime", "Periwinkle", "Peach"]
    static let colors: [Color] = [.init(red: 0.43, green: 0.83, blue: 0.73), .init(red: 0.44, green: 0.73, blue: 0.98),
        .init(red: 0.96, green: 0.76, blue: 0.39), .init(red: 0.80, green: 0.62, blue: 0.96),
        .init(red: 0.99, green: 0.57, blue: 0.65), .init(red: 0.69, green: 0.84, blue: 0.42),
        .init(red: 0.62, green: 0.68, blue: 1), .init(red: 0.99, green: 0.67, blue: 0.48)]
}

enum TerminalOutput {
    static let controls = try! NSRegularExpression(pattern: "\\x1B(?:\\][^\\x07\\x1B]*(?:\\x07|\\x1B\\\\)|\\[[0-?]*[ -/]*[@-~])")
    static func plain(_ text: String) -> String {
        controls.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }
    static func normalized(_ text: String) -> String {
        guard text.contains("\r") else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map {
            $0.components(separatedBy: "\r").last ?? ""
        }.joined(separator: "\n")
    }
    static func level(_ line: String) -> TerminalLogFilter {
        let value = plain(line).lowercased()
        if value.hasPrefix("[input]") { return .inputs }
        if value.range(of: "\\b(error|fatal|panic|exception|failed|failure)\\b", options: .regularExpression) != nil { return .errors }
        if value.range(of: "\\b(warn|warning|deprecated)\\b", options: .regularExpression) != nil { return .warnings }
        return .all
    }
    static func filtered(_ text: String, query: String, level: TerminalLogFilter) -> String {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty && level == .all { return normalized(text) }
        return normalized(text).components(separatedBy: "\n").filter { line in
            (query.isEmpty || plain(line).localizedCaseInsensitiveContains(query)) && (level == .all || self.level(line) == level)
        }.joined(separator: "\n")
    }
    static func attributed(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let normal = NSColor(calibratedRed: 0.60, green: 0.94, blue: 0.67, alpha: 1)
        let ansi: [NSColor] = [NSColor(white: 0.48, alpha: 1),
            NSColor(calibratedRed: 1, green: 0.44, blue: 0.48, alpha: 1),
            NSColor(calibratedRed: 0.42, green: 0.85, blue: 0.55, alpha: 1),
            NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.40, alpha: 1),
            NSColor(calibratedRed: 0.44, green: 0.73, blue: 0.98, alpha: 1),
            NSColor(calibratedRed: 0.81, green: 0.63, blue: 0.96, alpha: 1),
            NSColor(calibratedRed: 0.42, green: 0.84, blue: 0.87, alpha: 1), .white]
        var foreground = normal
        var bold = false
        var cursor = text.startIndex
        for match in controls.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            result.append(NSAttributedString(string: String(text[cursor..<range.lowerBound]), attributes: [.font: bold ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold) : font, .foregroundColor: foreground]))
            let sequence = String(text[range])
            if sequence.hasPrefix("\u{1B}["), sequence.hasSuffix("m") {
                let codes = sequence.dropFirst(2).dropLast().split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                var i = 0
                while i < codes.count {
                    let code = codes[i]
                    if code == 0 { foreground = normal; bold = false }
                    else if code == 1 { bold = true }
                    else if code == 22 { bold = false }
                    else if code == 39 { foreground = normal }
                    else if (30...37).contains(code) { foreground = ansi[code - 30] }
                    else if (90...97).contains(code) { foreground = ansi[code - 90] }
                    else if code == 38 || code == 48 {
                        if i + 4 < codes.count, codes[i + 1] == 2 {
                            if code == 38 { foreground = NSColor(calibratedRed: CGFloat(min(255, max(0, codes[i+2]))) / 255, green: CGFloat(min(255, max(0, codes[i+3]))) / 255, blue: CGFloat(min(255, max(0, codes[i+4]))) / 255, alpha: 1) }
                            i += 4
                        } else if i + 2 < codes.count, codes[i + 1] == 5 {
                            let n = min(255, max(0, codes[i+2]))
                            if code == 38 {
                                if n < 16 { foreground = ansi[n % 8] }
                                else if n >= 232 { foreground = NSColor(white: CGFloat(8 + (n - 232) * 10) / 255, alpha: 1) }
                                else {
                                    let rgb = n - 16
                                    func channel(_ value: Int) -> CGFloat { CGFloat(value == 0 ? 0 : 55 + value * 40) / 255 }
                                    foreground = NSColor(calibratedRed: channel(rgb / 36), green: channel((rgb / 6) % 6), blue: channel(rgb % 6), alpha: 1)
                                }
                            }
                            i += 2
                        }
                    }
                    i += 1
                }
            }
            cursor = range.upperBound
        }
        result.append(NSAttributedString(string: String(text[cursor...]), attributes: [.font: bold ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold) : font, .foregroundColor: foreground]))
        return result
    }
}
