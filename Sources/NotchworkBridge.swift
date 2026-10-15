import Foundation
import Combine
import NotchworkKit

/// Shares only service names and states. Commands, paths, logs, and diagnostics stay in Portkeeper.
@MainActor final class NotchworkBridge {
    private weak var model: PortkeeperModel?
    private var observation: AnyCancellable?
    private var timer: Timer?
    private var actionTask: Task<Void, Never>?
    private var cursor: UInt64 = 0
    private var connectionToken: String?
    private static let icon = Bundle.main.url(forResource: "Porty", withExtension: "png").flatMap { try? Data(contentsOf: $0) }?.base64EncodedString()
    private var lastPayload: Data?
    private var cleared = false
    private let file: URL
    private let connectionFile: URL?
    private let queue = DispatchQueue(label: "Portkeeper.NotchworkBridge", qos: .utility)
    init(model: PortkeeperModel, directory: URL, connectionFile: URL? = HostConnection.defaultFile) {
        self.model = model; self.connectionFile = connectionFile
        file = directory.appendingPathComponent("notchwork.json")
        observation = model.objectWillChange.throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true).sink { [weak self] _ in
            DispatchQueue.main.async { self?.update() }
        }
        update()
    }
    static func activity(_ model: PortkeeperModel) -> [String: Any] {
        var running = 0, starting = 0, issues = 0
        let rows = model.configs.map { config -> String in
            let state: String
            switch model.state(for: config) {
            case .running: running += 1; state = "Running"
            case .starting: starting += 1; state = "Starting"
            case .failed: issues += 1; state = "Failed · open Portkeeper for details"
            case .unhealthy: issues += 1; state = "Needs attention · open Portkeeper for details"
            case .occupied: issues += 1; state = "Port occupied"
            case .stopped: state = "Stopped"
            }
            return String("\(config.group) / \(config.name) · \(state)".prefix(500))
        }
        var details = Array(rows.prefix(29))
        if rows.count > 29 { details.append("\(rows.count - 29) more services in Portkeeper") }
        if model.scanError != nil { issues += 1 }
        var result: [String: Any] = ["id": "services", "sourceID": "app.portkeeper", "sourceName": "Portkeeper",
                "title": issues > 0 ? "\(issues) need attention" : "\(running) running",
                "subtitle": "\(starting) starting · \(model.configs.count) services",
                "symbol": issues > 0 ? "exclamationmark.triangle.fill" : "terminal",
                "priority": issues > 0 ? "urgent" : "normal", "preferredSide": "right",
                "details": details, "actions": [], "ttl": 60]
        let interface = PortkeeperNotchworkUI.interface(model)
        if let data = try? JSONEncoder().encode(interface), let object = try? JSONSerialization.jsonObject(with: data) { result["interface"] = object }
        if let icon { result["iconPNG"] = icon }
        return result
    }
    func update(force: Bool = false) {
        guard let model, model.shareWithNotchwork else {
            timer?.invalidate(); timer = nil; lastPayload = nil
            actionTask?.cancel(); actionTask = nil; cursor = 0; connectionToken = nil
            if !cleared {
                cleared = true
                let file = file
                queue.async { try? FileManager.default.removeItem(at: file) }
            }
            return
        }
        cleared = false
        if actionTask == nil && connectionFile != nil {
            actionTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let connected = await self.readActions()
                    if !connected {
                        do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                    }
                }
            }
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(force: true) }
            }
            timer?.tolerance = 2
        }
        let card = Self.activity(model)
        guard let payload = try? JSONSerialization.data(withJSONObject: card, options: .sortedKeys), force || payload != lastPayload else { return }
        lastPayload = payload
        guard let activity = try? JSONDecoder().decode(NotchActivity.self, from: payload),
              (try? activity.validate()) != nil,
              let data = try? JSONEncoder().encode(ActivitySnapshot(activity: activity)) else { return }
        let file = file
        queue.async {
            do {
                try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            } catch { /* The next heartbeat retries; service management never depends on the bridge. */ }
        }
    }
    private func readActions() async -> Bool {
        do {
            guard let connectionFile else { return false }
            let connection = try HostConnection.discover(at: connectionFile)
            if connectionToken != connection.token { cursor = 0; connectionToken = connection.token }
            let events = try await NotchworkClient(connection: connection).events(sourceID: "app.portkeeper", after: cursor, wait: true)
            guard !Task.isCancelled, let model, model.shareWithNotchwork else { return false }
            for event in events.sorted(by: { $0.sequence < $1.sequence }) {
                cursor = max(cursor, event.sequence)
                guard event.sourceID == "app.portkeeper", event.activityID == "services",
                      Date().timeIntervalSince1970 - event.createdAt < 30 else { continue }
                Self.perform(event.action, value: event.value, model: model)
            }
            return true
        } catch { return false }
    }
    @discardableResult static func perform(_ action: String, value: String, model: PortkeeperModel) -> Bool {
        guard model.shareWithNotchwork else { return false }
        if action == "open" { model.openNotchworkControls?(); return true }
        if action == "project.restart" {
            guard model.configs.contains(where: { $0.group == value }) else { return false }
            model.restartGroup(value); return true
        }
        guard let id = UUID(uuidString: value), let config = model.configs.first(where: { $0.id == id }) else { return false }
        switch action {
        case "service.start": model.start(config)
        case "service.stop": model.stop(config)
        case "service.restart": model.restart(config)
        default: return false
        }
        return true
    }
    func stop() {
        actionTask?.cancel(); actionTask = nil
        timer?.invalidate(); timer = nil; observation?.cancel(); observation = nil
        queue.sync { try? FileManager.default.removeItem(at: file) }
    }
}
