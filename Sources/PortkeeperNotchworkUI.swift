import Foundation
import NotchworkKit

/// Portkeeper owns this layout and the corresponding action handlers; Notchwork supplies the surface.
@MainActor enum PortkeeperNotchworkUI {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
    static func interface(_ model: PortkeeperModel) -> ActivityInterface {
        let services = Array(model.configs.prefix(12))
        let groups = Array(Set(services.map(\.group))).sorted()
        let rows = groups.map { group in
            let body = services.filter { $0.group == group }.map { config -> String in
                let status: String, active: Bool, attention: Bool
                switch model.state(for: config) {
                case .running: status = "RUNNING"; active = true; attention = false
                case .starting: status = "STARTING"; active = true; attention = false
                case .unhealthy: status = "NEEDS YOU"; active = true; attention = true
                case .failed: status = "FAILED"; active = false; attention = true
                case .occupied: status = "PORT BUSY"; active = false; attention = true
                case .stopped: status = "STOPPED"; active = false; attention = false
                }
                let id = config.id.uuidString
                return """
                <article><div class="service"><span class="dot \(attention ? "error" : active ? "on" : "")"></span><strong>\(escape(String(config.name.prefix(70))))</strong><small>\(status)</small></div>
                <div class="controls"><button data-action="service.\(active ? "stop" : "start")" data-value="\(id)">\(active ? "Stop" : "Start")</button><button data-action="service.restart" data-value="\(id)">Restart</button></div></article>
                """
            }.joined()
            return "<section><header><span>\(escape(String(group.prefix(80))))</span><button data-action=\"project.restart\" data-value=\"\(escape(group))\">Restart project ↻</button></header>\(body)</section>"
        }.joined()
        let attention = model.configs.contains { config in
            switch model.state(for: config) { case .failed, .unhealthy, .occupied: return true; default: return false }
        }
        let html = """
        <style>
        body{font:12px ui-monospace,Menlo,monospace;background:#000;color:#e3ffed}main{padding:20px}h1{font-size:22px;letter-spacing:-1px;margin:0}p{color:#99b4a3;font-size:11px;line-height:1.6}.brand{display:flex;align-items:center;gap:13px;margin-bottom:22px}.porty{width:43px;height:39px;background:\(attention ? "#f5bc68" : "#76f9a6");border-radius:48% 48% 37% 37%;position:relative;flex:none}.eyes{position:absolute;display:flex;gap:7px;left:10px;top:12px;animation:blink 7s infinite}.eyes i{width:8px;height:\(attention ? "13" : "11")px;background:#06100a;border-radius:5px}.porty:after{content:'';position:absolute;width:9px;height:4px;border-bottom:2px solid #06100a;left:17px;top:26px;border-radius:50%}header{display:flex;gap:12px;align-items:center;justify-content:space-between;color:#7cf9a8;font-size:10px;text-transform:uppercase;letter-spacing:1px;border-bottom:1px solid #253a2c;padding-bottom:9px;margin-top:18px}header span{overflow-wrap:anywhere}article{padding:13px 0;border-bottom:1px solid #14251a}.service{display:flex;align-items:center;gap:8px}.service strong{flex:1;font-weight:500;overflow-wrap:anywhere}.service small{font-size:8px;color:#a8bdb0}.dot{width:5px;height:5px;border-radius:50%;background:#486351;flex:none}.dot.on{background:#76f9a6}.dot.error{background:#f5bc68}.controls{display:flex;gap:8px;margin:9px 0 0 13px}button{font:10px ui-monospace,Menlo,monospace;border:1px solid #35573f;border-radius:6px;background:#0c1c12;color:#baffd1;padding:6px 9px;cursor:pointer}button:hover{background:#173823}button:focus-visible{outline:2px solid #baffd1;outline-offset:2px}button:disabled{opacity:.45;cursor:wait}.full{margin-top:20px;width:100%;padding:11px}#feedback{min-height:18px;color:#99b4a3;font-size:10px;margin-top:12px}@keyframes blink{0%,93%,97%,100%{transform:scaleY(1)}95%{transform:scaleY(.1)}}@media(prefers-reduced-motion:reduce){.eyes{animation:none}}
        </style><main><div class="brand"><div class="porty" aria-hidden="true"><span class="eyes"><i></i><i></i></span></div><div><h1>Portkeeper</h1><p>\(model.configs.count) services · your ports, in view.</p></div></div>
        \(rows.isEmpty ? "<p>No services yet. Open Portkeeper to add a project or paste a JSON handoff.</p>" : rows)
        \(model.configs.count > services.count ? "<p>\(model.configs.count - services.count) more services in Portkeeper.</p>" : "")
        <button class="full" data-action="open" data-value="">Terminals, project handoff & AI ↗</button><div id="feedback" role="status" aria-live="polite"></div></main>
        <script>document.addEventListener('click',e=>{const b=e.target.closest('button[data-action]');if(!b)return;notchwork.invoke(b.dataset.action,b.dataset.value);document.getElementById('feedback').textContent='Sent to Portkeeper…';b.disabled=true;setTimeout(()=>{b.disabled=false;document.getElementById('feedback').textContent='Check the service status or open Portkeeper for details.'},2000)});</script>
        """
        return ActivityInterface(html: html, height: min(700, Double(220 + services.count * 78 + groups.count * 45)),
                                 actions: ["service.start", "service.stop", "service.restart", "project.restart", "open"])
    }
}
