import Foundation
import AppKit
import Combine
import NotchworkKit

/// Portkeeper owns its content and actions. Only the Notchwork process owns the notch window.
@MainActor final class NotchworkBridge {
    typealias Connect = @MainActor () async throws -> NotchworkClient
    typealias Send = @MainActor (NotchworkClient, HostCommand) async throws -> HostResponse
    private weak var model: PortkeeperModel?
    private var observation: AnyCancellable?
    private var worker: Task<Void, Never>?
    private var publication: Task<Void, Never>?
    private var publicationGeneration = UUID()
    private var timer: Timer?
    private var client: NotchworkClient?
    private var stopped = false
    private var lastPayload: Data?
    private var pending: NotchActivity?
    private let connect: Connect
    private let send: Send
    private static let icon = Bundle.main.url(forResource: "Porty", withExtension: "png").flatMap { try? Data(contentsOf: $0) }?.base64EncodedString()
    init(model: PortkeeperModel, connect: @escaping Connect = NotchworkBridge.connectRuntime,
         send: @escaping Send = { try await $0.send($1) }) {
        self.model = model; self.connect = connect; self.send = send
        observation = model.objectWillChange.throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true).sink { [weak self] _ in
            DispatchQueue.main.async { self?.update() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(force: true) }
        }
        worker = Task { [weak self] in await self?.run() }
    }
    static func connectRuntime() async throws -> NotchworkClient {
        try await NotchworkRuntime.ensureRunning()
        for _ in 0..<30 {
            try Task.checkCancellation()
            if let connection = try? HostConnection.discover() {
                let client = NotchworkClient(connection: connection)
                if let response = try? await client.send(HostCommand(operation: "ping")), (response.apiVersion ?? 0) >= 2 {
                    guard ["interface-forms", "side-hover", "user-controlled-pinning"].allSatisfy({ response.capabilities?.contains($0) == true }) else {
                        throw ActivityError.invalid("Update and restart Notchwork (0.2.1 build 10 or newer) to show Portkeeper’s dashboard.")
                    }
                    return client
                }
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw ActivityError.invalid("Notchwork has not started its API. Retry from Portkeeper settings.")
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
            return String("\(config.group) / \(config.name) · \(state)".prefix(160))
        }
        var details = Array(rows.prefix(29))
        if rows.count > 29 { details.append("\(rows.count - 29) more services in Portkeeper") }
        if model.scanError != nil { issues += 1 }
        var result: [String: Any] = ["id": "services", "sourceID": "app.portkeeper", "sourceName": "Portkeeper",
                "title": issues > 0 ? "\(issues) need attention" : "\(running) running",
                "subtitle": "\(starting) starting · \(model.configs.count) services",
                "symbol": issues > 0 ? "exclamationmark.triangle.fill" : "terminal",
                "priority": Self.priority(issues: issues, starting: starting).rawValue, "preferredSide": "right",
                "details": details, "actions": [], "ttl": 60]
        let interface = PortkeeperNotchworkUI.interface(model)
        if let data = try? JSONEncoder().encode(interface), let object = try? JSONSerialization.jsonObject(with: data) { result["interface"] = object }
        if let icon { result["iconPNG"] = icon }
        return result
    }
    // Legacy wire values remain compatible with Notchwork 0.1.1; the new host
    // presents them as high, mid, and low notifications respectively.
    static func priority(issues: Int, starting: Int) -> ActivityPriority {
        issues > 0 ? .urgent : (starting > 0 ? .important : .normal)
    }

    private func run() async {
        while !Task.isCancelled && !stopped {
            do {
                model?.notchworkStatus = "Connecting to Notchwork…"
                let connected = try await connect()
                try Task.checkCancellation()
                _ = try await send(connected, HostCommand(operation: "register", registration:
                    SourceRegistration(id: "app.portkeeper", name: "Portkeeper", customInterface: true)))
                client = connected; lastPayload = nil
                model?.notchworkStatus = "Notchwork connected"
                update(force: true)
                var cursor: UInt64 = 0
                while !Task.isCancelled && client?.connection.token == connected.connection.token {
                    let response = try await send(connected, HostCommand(operation: "events", sourceID: "app.portkeeper", after: cursor, wait: true))
                    try Task.checkCancellation()
                    guard let model else { return }
                    for event in (response.events ?? []).sorted(by: { $0.sequence < $1.sequence }) {
                        cursor = max(cursor, event.sequence)
                        guard event.sourceID == "app.portkeeper", event.activityID == "services",
                              (0..<30).contains(Date().timeIntervalSince1970 - event.createdAt) else { continue }
                        Self.perform(event.action, value: event.value, model: model)
                        update()
                    }
                }
            } catch {
                if Task.isCancelled || stopped { return }
                publication?.cancel(); publication = nil; publicationGeneration = UUID(); pending = nil
                client = nil; lastPayload = nil
                model?.notchworkStatus = error.localizedDescription
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            }
        }
    }
    func update(force: Bool = false) {
        guard !stopped, let model, let client,
              let payload = try? JSONSerialization.data(withJSONObject: Self.activity(model), options: .sortedKeys),
              force || payload != lastPayload,
              let activity = try? JSONDecoder().decode(NotchActivity.self, from: payload) else { return }
        pending = activity; lastPayload = payload
        guard publication == nil else { return }
        let generation = UUID(); publicationGeneration = generation
        publication = Task { [weak self] in
            guard let self else { return }
            defer { if self.publicationGeneration == generation { self.publication = nil } }
            do {
                while let activity = self.pending, !Task.isCancelled {
                    self.pending = nil
                    _ = try await self.send(client, HostCommand(operation: "publish", activity: activity))
                }
            } catch {
                guard self.publicationGeneration == generation, !Task.isCancelled else { return }
                self.client = nil; self.lastPayload = nil
                self.model?.notchworkStatus = error.localizedDescription
            }
        }
    }
    func present() async throws {
        guard !stopped, let model else { return }
        let connected = try await connect()
        _ = try await send(connected, HostCommand(operation: "register", registration:
            SourceRegistration(id: "app.portkeeper", name: "Portkeeper", customInterface: true)))
        let data = try JSONSerialization.data(withJSONObject: Self.activity(model))
        let activity = try JSONDecoder().decode(NotchActivity.self, from: data)
        _ = try await send(connected, HostCommand(operation: "publish", activity: activity))
        _ = try await send(connected, HostCommand(operation: "present", sourceID: "app.portkeeper", id: "services"))
    }
    @discardableResult static func perform(_ action: String, value: String, model: PortkeeperModel) -> Bool {
        if action == "page", let data = value.data(using: .utf8), let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { return model.notchworkPages.perform(payload) }
        if action == "refresh" { model.refresh(); return true }
        if ["ui", "service", "project", "listener", "open"].contains(action),
           let data = value.data(using: .utf8),
           let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] {
            if action == "ui" {
                guard let tab = payload["tab"], ["services", "ports"].contains(tab),
                      let query = payload["query"], query.utf8.count <= 256 else { return false }
                model.notchworkTab = tab; model.notchworkSearch = query; return true
            }
            let operation = payload["op"] ?? "", identity = payload["id"] ?? ""
            func copy(_ text: String, notice: String) {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                model.notchworkNotice = notice
            }
            if action == "open" {
                guard ["add", "handoff", "settings", "workspace", "ports"].contains(operation) else { return false }
                switch operation {
                case "add": model.notchworkPages.add()
                case "handoff", "settings": model.notchworkPages.show(operation)
                case "ports": model.notchworkPages.dashboard(ports: true)
                default: model.openNotchworkPage?(operation, "")
                }; return true
            }
            if action == "project" {
                guard model.configs.contains(where: { $0.group == identity }) else { return false }
                switch operation {
                case "restart": model.restartGroup(identity)
                case "start": if !model.isGroupRunning(identity) { model.toggleGroup(identity) }
                case "stop": if model.isGroupRunning(identity) { model.toggleGroup(identity) }
                case "more": model.notchworkPages.show("projectActions", id: identity)
                default: return false
                }
                return true
            }
            if action == "listener" {
                guard let listener = model.listeners.first(where: { $0.id == identity }) else { return false }
                switch operation {
                case "ai": copy(model.explanationPrompt(for: listener), notice: "Port \(listener.port) prompt copied")
                case "stop": model.notchworkPages.confirm(listener)
                default: return false
                }
                return true
            }
            guard let id = UUID(uuidString: identity), let config = model.configs.first(where: { $0.id == id }) else { return false }
            switch operation {
            case "start": if case .occupied = model.state(for: config) { return false }; model.start(config)
            case "stop": model.stop(config)
            case "restart": model.restart(config)
            case "address": model.open(config)
            case "ai": copy(model.issuePrompt(for: config), notice: "\(config.name) AI prompt copied")
            case "output": model.notchworkPages.show("output", id: identity)
            case "terminal": model.notchworkPages.activate(id, open: true)
            case "more": model.notchworkPages.show("serviceActions", id: identity)
            default: return false
            }
            return true
        }
        if action == "open", value.isEmpty { model.openNotchworkControls?(); return true }
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
        stopped = true; worker?.cancel(); publication?.cancel(); timer?.invalidate(); observation?.cancel()
        worker = nil; publication = nil; pending = nil
        if let client {
            let send = send
            Task { _ = try? await send(client, HostCommand(operation: "remove", sourceID: "app.portkeeper", id: "services")) }
        }
        client = nil
    }
}
