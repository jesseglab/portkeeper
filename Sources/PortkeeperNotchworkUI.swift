import Foundation
import NotchworkKit

/// The familiar Portkeeper dashboard, rendered by the shared host. Commands and diagnostics stay in the app.
@MainActor enum PortkeeperNotchworkUI {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
    static func interface(_ model: PortkeeperModel) -> ActivityInterface {
        var services: [[String: Any]] = model.configs.map { config in
            let status: String, active: Bool, issue: Bool, occupied: Bool
            switch model.state(for: config) {
            case .running: status = "Running"; active = true; issue = false; occupied = false
            case .starting: status = "Starting"; active = true; issue = false; occupied = false
            case .unhealthy: status = "Needs attention"; active = true; issue = true; occupied = false
            case .failed: status = "Failed · view output"; active = false; issue = true; occupied = false
            case .occupied: status = "Port in use"; active = false; issue = true; occupied = true
            case .stopped: status = "Stopped"; active = false; issue = false; occupied = false
            }
            return ["id": config.id.uuidString, "name": String(config.name.prefix(120)), "group": String(config.group.prefix(120)),
                    "status": status, "port": config.port.map(String.init) ?? "tunnel", "active": active, "issue": issue,
                    "occupied": occupied, "hasAddress": config.port != nil || !config.url.isEmpty]
        }
        var listeners: [[String: Any]] = model.listeners.map {
            ["id": $0.id, "port": $0.port, "process": String($0.process.prefix(120)), "pid": $0.pid, "address": String($0.address.prefix(120))]
        }
        func encoded() -> String {
            let state: [String: Any] = ["services": services, "listeners": listeners,
                "serviceCount": model.configs.count, "listenerCount": model.listeners.count,
                "running": model.configs.filter { model.state(for: $0).terminalActive }.count,
                "issues": model.activeIssues.count + (model.scanError == nil ? 0 : 1),
                "scanFailed": model.scanError != nil, "recent": String((model.recentProject ?? "").prefix(120)),
                "tab": model.notchworkTab, "query": model.notchworkSearch, "notice": model.notchworkNotice]
            guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else { return "{}" }
            return json
        }
        var state = encoded()
        // Keep the API bounded for unusually large workspaces; disclose overflow in the UI.
        while state.utf8.count > 20_000 && (!services.isEmpty || !listeners.isEmpty) {
            if services.count >= listeners.count { services.removeLast() } else { listeners.removeLast() }
            state = encoded()
        }
        return ActivityInterface(html: document, height: 590,
            actions: ["service", "project", "listener", "open", "refresh", "ui", "service.start", "service.stop", "service.restart", "project.restart"],
            width: 400, stateJSON: state)
    }
    static let document = #"""
    <style>
    :root{--ink:#c4f5cc;--muted:#73a37d;--green:#5cff7a;--line:#1f4026;--well:#030604;--raised:#06160a}
    html,body{height:100%;overflow:hidden}body{font:11px Menlo,ui-monospace,monospace;color:var(--ink);background:#000}button,input{font:inherit}button{color:var(--green);background:#000;border:1px solid var(--line);border-radius:6px;cursor:pointer}button:hover{background:var(--raised)}button:disabled{opacity:.35;cursor:default}button:focus-visible,input:focus-visible{outline:2px solid var(--green);outline-offset:2px}button svg{width:13px;height:13px;display:block}svg{fill:none;stroke:currentColor;stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round;flex:none}.icon{width:26px;height:28px;display:inline-flex;align-items:center;justify-content:center;flex:none}.quiet{border-color:transparent}.brand{display:flex;gap:12px;align-items:center;padding:17px 18px 14px;border-bottom:1px solid #142a19}.brand>svg{width:40px;height:40px;color:var(--green)}h1{font-size:18px;letter-spacing:-.3px;margin:0 0 4px;font-weight:600}.subtitle{color:var(--muted);font-size:10px;line-height:1.5}.brand .icon{margin-left:auto}.app{height:100%;display:flex;flex-direction:column}.tabs{display:flex;gap:6px;padding:13px 18px 12px}.tabs button{flex:1;height:30px;color:var(--muted);font-size:12px}.tabs button[aria-selected=true]{background:var(--raised);color:var(--ink)}.tabs svg{width:12px;height:12px;vertical-align:-2px;margin-right:7px}.pane{flex:1;min-height:0;overflow:auto;padding:0 16px 18px;scrollbar-width:thin;scrollbar-color:#25472d #000}.pane[hidden]{display:none}section{margin-bottom:15px}.group{display:flex;gap:5px;align-items:center;padding:0 8px 4px;font-size:10px;letter-spacing:1.3px;color:var(--muted)}.group b{font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1}.group>span{color:var(--green)}.group .icon{width:20px;height:20px}.service{display:flex;gap:8px;align-items:center;padding:9px 10px;background:var(--well);border:1px solid #102416;border-radius:6px;margin-top:4px}.dot{width:8px;height:8px;flex:none;border-radius:50%;background:#39513e;margin:0 3px}.dot.active,.dot.issue{background:var(--green)}.name{flex:1;min-width:0}.name strong{font-size:13px;font-weight:600;display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.name small{font-size:10px;color:var(--muted);display:block;margin-top:3px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.controls{display:flex;gap:1px;flex:none}.controls .icon{width:22px}.controls .toggle{width:28px;margin-left:2px;color:var(--ink)}footer{display:flex;align-items:center;gap:12px;padding:12px 17px;border-top:1px solid #142a19}.primary{background:var(--green);color:#000;font-weight:600;padding:7px 10px}.primary:hover{background:#9affad}footer .handoff{border:0;font-size:11px;padding:0}footer .icon{margin-left:auto}.filter{display:flex;align-items:center;gap:8px;padding:10px;margin-bottom:10px;border:1px solid var(--line);border-radius:6px;background:var(--well)}.filter input{width:100%;background:transparent;color:var(--ink);border:0;outline:none;min-width:0}.filter svg{width:12px;height:12px;color:var(--muted)}.listener{display:flex;align-items:center;gap:8px;background:var(--well);border:1px solid #102416;border-radius:6px;padding:8px 10px;margin-bottom:4px}.port{color:var(--green);font-size:14px;font-weight:600;width:53px;flex:none}.listener .name strong{font-size:12px}.empty{color:var(--muted);text-align:center;padding:60px 12px;line-height:1.7}.overflow{font-size:10px;color:var(--muted);line-height:1.6}.overflow button{padding:5px 8px}.notice{font-size:10px;color:var(--muted);padding:0 18px 8px}.notice:empty{display:none}@media(max-width:360px){.brand{padding-left:12px;padding-right:12px}.pane{padding-left:8px;padding-right:8px}.service{gap:4px;padding-left:5px;padding-right:5px}.controls .optional{display:none}footer{gap:7px;padding-left:10px;padding-right:10px}}
    </style>
    <main class="app">
      <header class="brand"><svg viewBox="0 0 40 40" aria-hidden="true"><rect x="5" y="7" width="30" height="26" rx="3"/><path d="m11 14 6 6-6 6m12 0h7"/></svg><div><h1>portkeeper_</h1><div class="subtitle" id="summary">Connecting…</div></div><button class="icon" data-action="refresh" title="Scan ports now" aria-label="Scan ports now">↻</button></header>
      <nav class="tabs" role="tablist"><button role="tab" aria-selected="true" data-tab="services" aria-controls="services">▱ Services</button><button role="tab" aria-selected="false" data-tab="ports" aria-controls="ports">⌘ Ports</button></nav>
      <div id="services" class="pane" role="tabpanel" aria-label="Services"></div>
      <div id="ports" class="pane" role="tabpanel" aria-label="Ports" hidden><label class="filter"><span aria-hidden="true">⌕</span><input id="query" placeholder="Filter by port or process" aria-label="Filter by port or process"></label><div id="listeners"></div></div>
      <div id="notice" class="notice" role="status" aria-live="polite"></div>
      <footer><button class="primary" data-action="open" data-op="add">+ Add service</button><button class="handoff" data-action="open" data-op="handoff">↥ Project handoff</button><button class="icon quiet" data-action="open" data-op="settings" title="Portkeeper settings" aria-label="Portkeeper settings">⚙</button></footer>
    </main>
    <script>
    let state={},tab='services',query='',queryTimer;
    const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const paths={play:'m8 5 11 7-11 7z',stop:'M6 6h12v12H6z',restart:'M20 11a8 8 0 1 0-2 6M20 4v7h-7',more:'M5 12h.01M12 12h.01M19 12h.01',terminal:'M4 5h16v14H4zM7 9l3 3-3 3m6 0h4',open:'M7 17 17 7M7 7h10v10',ai:'m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5z',side:'M4 5h16v14H4zM14 5v14'};
    function icon(name){return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="'+paths[name]+'"/></svg>'}
    function button(action,op,id,label,symbol,extra='',disabled=false){return '<button class="icon '+extra+'" data-action="'+action+'" data-op="'+op+'" data-id="'+esc(id)+'" aria-label="'+esc(label)+'" title="'+esc(label)+'" '+(disabled?'disabled':'')+'>'+icon(symbol)+'</button>'}
    function replace(id,html){const el=document.getElementById(id);if(el.innerHTML!==html){const top=el.scrollTop;el.innerHTML=html;el.scrollTop=top}}
    function render(){
      document.getElementById('summary').textContent=(state.listenerCount||0)+' listening ports · '+(state.running||0)+' managed'+(state.issues?' · '+state.issues+' issues':'');
      document.getElementById('notice').textContent=state.notice||'';
      const services=state.services||[],groups=[...new Set(services.map(s=>s.group))].sort((a,b)=>a===state.recent?-1:b===state.recent?1:a.localeCompare(b));
      let rows=groups.map(g=>{const entries=services.filter(s=>s.group===g),active=entries.some(s=>s.active);return '<section><div class="group"><span>›</span><b>'+esc(g.toUpperCase())+'</b>'+button('project','more',g,'Edit or delete '+g,'more','quiet')+button('project','restart',g,'Restart all services in '+g,'restart','quiet')+button('project',active?'stop':'start',g,(active?'Stop':'Start')+' all in '+g,active?'stop':'play')+'</div>'+entries.map(s=>'<article class="service"><span class="dot '+(s.issue?'issue':s.active?'active':'')+'"></span><div class="name"><strong>'+esc(s.name)+'</strong><small>'+esc(':'+s.port+' · '+s.status)+'</small></div><div class="controls">'+button('service','terminal',s.id,'Open '+s.name+' terminal','side','quiet optional')+(s.issue?button('service','ai',s.id,'Copy AI prompt for '+s.name,'ai','quiet optional'):'')+(s.hasAddress?button('service','address',s.id,'Open '+s.name+' local address','open','quiet optional'):'')+button('service','more',s.id,'Edit, output, or remove '+s.name,'more','quiet')+button('service',s.active?'stop':'start',s.id,s.occupied?'Port belongs to another process':(s.active?'Stop ':'Start ')+s.name,s.active?'stop':'play','toggle',s.occupied)+'</div></article>').join('')+'</section>'}).join('');
      if(!services.length)rows='<div class="empty">No services yet.<br>Add a command to start it from the notch.</div>';
      if(services.length<state.serviceCount)rows+='<p class="overflow">'+(state.serviceCount-services.length)+' more services in the full workspace. <button data-action="open" data-op="workspace">Open workspace</button></p>';
      replace('services',rows);renderPorts();selectTab(tab,false);
    }
    function renderPorts(){const q=query.toLowerCase();const rows=(state.listeners||[]).filter(p=>(p.port+' '+p.process+' '+p.address).toLowerCase().includes(q));let html=state.scanFailed?'<p class="overflow">Port scan needs attention. <button data-action="open" data-op="ports">View details</button></p>':'';html+=rows.map(p=>'<article class="listener"><span class="port">:'+p.port+'</span><div class="name"><strong>'+esc(p.process)+'</strong><small>PID '+p.pid+' · '+esc(p.address)+'</small></div>'+button('listener','ai',p.id,'Explain port '+p.port,'ai','quiet')+button('listener','stop',p.id,'Review stopping '+p.process,'stop','quiet')+'</article>').join('');if(!rows.length)html+='<div class="empty">No matching listening ports.</div>';if((state.listeners||[]).length<state.listenerCount)html+='<p class="overflow">More listeners are available in <button data-action="open" data-op="ports">Portkeeper’s workspace</button>.</p>';replace('listeners',html)}
    function selectTab(value,send=true){tab=value;document.querySelectorAll('[data-tab]').forEach(b=>b.setAttribute('aria-selected',String(b.dataset.tab===tab)));document.getElementById('services').hidden=tab!=='services';document.getElementById('ports').hidden=tab!=='ports';if(send)notchwork.invoke('ui',JSON.stringify({tab,query}))}
    window.addEventListener('notchwork:state',e=>{state=e.detail||{};tab=state.tab||tab;if(document.activeElement!==document.getElementById('query')){query=state.query||'';document.getElementById('query').value=query}render()});
    document.addEventListener('click',e=>{const t=e.target.closest('[data-tab]');if(t){selectTab(t.dataset.tab);return}const b=e.target.closest('button[data-action]');if(!b||b.disabled)return;notchwork.invoke(b.dataset.action,JSON.stringify({op:b.dataset.op||'',id:b.dataset.id||''}));});
    document.getElementById('query').addEventListener('input',e=>{query=e.target.value;renderPorts();clearTimeout(queryTimer);queryTimer=setTimeout(()=>notchwork.invoke('ui',JSON.stringify({tab,query})),180)});
    if(notchwork.state){state=notchwork.state;tab=state.tab||tab;query=state.query||'';document.getElementById('query').value=query;render()}
    </script>
    """#
}
