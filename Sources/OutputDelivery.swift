import Foundation
import Darwin

/// Bounded pipe intake; only one UI delivery is scheduled for each burst.
final class OutputDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var scheduled = false
    private var ready = false
    private var markerTail = Data()
    private let marker = Data("\u{1E}PORTKEEPER_INPUT_READY\u{1F}\n".utf8)
    static let capacity = 160_000

    func append(_ data: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let probe = markerTail + data
        if probe.range(of: marker) != nil { ready = true }
        markerTail = Data(probe.suffix(marker.count - 1))
        pending.append(data)
        if pending.count > Self.capacity { pending = Data(pending.suffix(Self.capacity)) }
        guard !scheduled else { return false }
        scheduled = true
        return true
    }
    func drain(final: Bool = false) -> (text: String, ready: Bool) {
        lock.lock(); defer { lock.unlock() }
        var end = pending.count
        if !final, end > 0 {
            // Keep a split UTF-8 scalar for the next delivery instead of replacing it.
            var start = end - 1
            while start > 0 && pending[start] & 0xC0 == 0x80 && end - start < 4 { start -= 1 }
            let lead = pending[start]
            let needed = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
            if end - start < needed { end = start }
        }
        var text = String(decoding: pending.prefix(end), as: UTF8.self)
        // The readiness marker may itself span multiple reads/deliveries.
        if !final {
            let bytes = Data(text.utf8)
            for count in stride(from: min(marker.count - 1, bytes.count), through: 1, by: -1) {
                if bytes.suffix(count) == marker.prefix(count) { end -= count; text = String(decoding: pending.prefix(end), as: UTF8.self); break }
            }
        }
        pending = Data(pending.dropFirst(end))
        scheduled = false
        let wasReady = ready; ready = false
        return (text.replacingOccurrences(of: String(decoding: marker, as: UTF8.self), with: ""), wasReady)
    }
}

/// Coalesces disk snapshots on a utility queue, independently of UI delivery.
final class LogPersistence: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ai.portkeeper.log-writes", qos: .utility)
    private let lock = NSLock()
    private var pending: [URL: Data] = [:]
    private var scheduled = false
    func save(_ data: Data, to url: URL) {
        lock.lock()
        pending[url] = data
        let schedule = !scheduled
        scheduled = true
        lock.unlock()
        if schedule { queue.asyncAfter(deadline: .now() + 0.3) { self.writePending() } }
    }
    func remove(_ url: URL) {
        lock.lock(); pending.removeValue(forKey: url); lock.unlock()
        queue.async { try? FileManager.default.removeItem(at: url) }
    }
    func flush() { queue.sync { self.writePending() } }
    private func writePending() {
        lock.lock(); let snapshots = pending; pending.removeAll(); scheduled = false; lock.unlock()
        for (url, data) in snapshots {
            let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { continue }
            data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var offset = 0
                while offset < data.count {
                    let written = Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
                    if written < 0 && errno == EINTR { continue }
                    guard written > 0 else { break }
                    offset += written
                }
            }
            _ = Darwin.close(descriptor)
        }
    }
}
