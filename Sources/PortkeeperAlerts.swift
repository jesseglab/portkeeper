import AppKit
@preconcurrency import UserNotifications

@MainActor final class PortkeeperAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PortkeeperAlerts()
    private static let categoryID = "PORTKEEPER_ISSUE"
    private static let copyActionID = "COPY_AI_PROMPT"
    private weak var model: PortkeeperModel?
    weak var menuBar: PortkeeperMenuBar?
    private var authorized = false
    private var permissionResolved = false
    private var waiting: [UNNotificationRequest] = []

    func configure(model: PortkeeperModel) {
        self.model = model
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let copy = UNNotificationAction(identifier: Self.copyActionID, title: "Copy AI prompt", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [copy], intentIdentifiers: [], options: [])
        ])
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                guard let self else { return }
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    self.authorized = true
                    self.permissionResolved = true
                    self.flush()
                case .notDetermined:
                    self.authorized = (try? await center.requestAuthorization(options: [.alert])) ?? false
                    self.permissionResolved = true
                    self.flush()
                default:
                    self.permissionResolved = true
                    self.waiting.removeAll()
                }
            }
        }
    }

    func notify(issue: ServiceIssue, config: ServiceConfig) {
        let content = UNMutableNotificationContent()
        content.title = "\(config.name) needs attention"
        content.body = String(issue.message.prefix(170))
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = config.group
        content.userInfo = ["configID": config.id.uuidString, "observedIssue": issue.message]
        let identifier = "portkeeper.service.\(config.id.uuidString)"
        clear(identifier: identifier)
        enqueue(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func notifyScan(error: String) {
        let safe = String(PortkeeperModel.redactedDiagnosticText(error).prefix(170))
        let content = UNMutableNotificationContent()
        content.title = "Port scan needs attention"
        content.body = safe
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["scanError": safe]
        clearScan()
        enqueue(UNNotificationRequest(identifier: "portkeeper.scan", content: content, trigger: nil))
    }

    func clear(configID: UUID) {
        clear(identifier: "portkeeper.service.\(configID.uuidString)")
    }

    func clearScan() { clear(identifier: "portkeeper.scan") }

    private func clear(identifier: String) {
        waiting.removeAll { $0.identifier == identifier }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func enqueue(_ request: UNNotificationRequest) {
        if authorized { UNUserNotificationCenter.current().add(request) }
        else if !permissionResolved { waiting.removeAll { $0.identifier == request.identifier }; waiting.append(request) }
    }

    private func flush() {
        guard authorized else { waiting.removeAll(); return }
        for request in waiting { UNUserNotificationCenter.current().add(request) }
        waiting.removeAll()
    }

    private func handle(_ response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == Self.copyActionID {
            let prompt: String?
            if let idText = info["configID"] as? String,
               let id = UUID(uuidString: idText),
               let config = model?.configs.first(where: { $0.id == id }) {
                prompt = model?.issuePrompt(for: config, observedIssue: info["observedIssue"] as? String)
            } else if let error = info["scanError"] as? String {
                prompt = PortkeeperModel.scanIssuePrompt(error)
            } else { prompt = nil }
            if let prompt {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prompt, forType: .string)
            }
        }
        if response.actionIdentifier == Self.copyActionID ||
           response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            if let idText = info["configID"] as? String,
               let id = UUID(uuidString: idText),
               model?.configs.contains(where: { $0.id == id }) == true {
                menuBar?.openServiceIssue(id, message: info["observedIssue"] as? String)
            } else if info["scanError"] != nil {
                menuBar?.openScanIssue()
            } else {
                menuBar?.openPanel()
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            self.handle(response)
            completionHandler()
        }
    }
}
