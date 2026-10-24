import AppKit
import Combine
import Darwin

extension TerminalWorkspaceTests {
    @MainActor static func runPerformanceProbe() async {
        let model = makeModel()
        self.model = model
        let suite = "PortkeeperPerformance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = TerminalWorkspaceController(model: model, defaults: defaults)
        func cpu() -> Double {
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        func sample(_ label: String, seconds: Double) async {
            let start = ProcessInfo.processInfo.systemUptime, initialCPU = cpu()
            var gaps: [Double] = [], previous = start
            while ProcessInfo.processInfo.systemUptime - start < seconds {
                try? await Task.sleep(nanoseconds: 16_666_667)
                let now = ProcessInfo.processInfo.systemUptime
                gaps.append((now - previous) * 1000); previous = now
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            gaps.sort()
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print(String(format: "PERF %@ CPU=%.2f%% p95-main-gap=%.2fms max-main-gap=%.2fms peak-RSS=%.1fMiB", label, (cpu() - initialCPU) / elapsed * 100, gaps[Int(Double(gaps.count - 1) * 0.95)], gaps.last!, Double(usage.ru_maxrss) / 1_048_576))
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        await sample("idle", seconds: 3)
        let command = "i=0; while (( i < 400 )); do printf 'line %s: %02000d\\n' $i 0; ((i++)); sleep 0.02; done; echo OUTPUT_COMPLETE"
        let services = (1...2).map { config("Stream \($0)", "Performance", command) }
        for service in services { model.upsert(service) }
        workspace.state.activeTerminals = Set(services.map(\.id))
        var publications = 0
        let subscription = model.$logs.dropFirst().sink { _ in publications += 1 }
        for service in services { model.start(service) }
        await sample("collapsed-streams", seconds: 3)
        workspace.show()
        await sample("visible-streams", seconds: 3)
        print("PERF log-publications=\(publications)")
        subscription.cancel()
        for service in services { model.stop(service) }

    }
}
