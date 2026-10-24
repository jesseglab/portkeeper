# Required Notchwork runtime

Portkeeper uses Notchwork API 2 for every notch surface. Its own notch geometry, windows, hover handling, and morphing renderer have been removed. Normal workspace and detached terminal windows remain owned by Portkeeper.

## First launch

- Verify and reuse `~/Applications/Notchwork.app` or `/Applications/Notchwork.app` when compatible.
- Otherwise stage a copy of `Contents/Resources/Notchwork/Notchwork.app`, remove Finder metadata only from that copy, verify its code signature, and install it into the user’s Applications folder. Quarantine metadata and signed contents are preserved.
- Preserve an incompatible destination and report an actionable error rather than overwriting it.
- Start the runtime in the background, wait for API 2, register the app-owned custom controls, and publish current state.

The package supplies the prerequisite offline. It does not download mutable executable code. Existing registered user restrictions remain respected on reconnect.

## Runtime behavior

`NotchworkBridge` publishes directly to the loopback API and consumes named action events. It republishes after host restart, sends unchanged keep-alives every 20 seconds, and removes its activity on clean shutdown. A 60-second activity lifetime cleans up after a crash. A menu-bar click calls `present`; background updates never do.

| State | Priority |
| --- | --- |
| Failed, unhealthy, occupied, or scan error | High |
| Starting with no issue | Mid |
| Healthy/running or idle/stopped | Low |

Portkeeper owns UI content and executes only declared service/project actions. The shared container handles placement, motion, priority, and expiry. Logs, shell commands, and private diagnostics are not sent to the host.

## Reuse this pattern in your app

Start from [the generic quickstart](https://github.com/jesseglab/notchwork/blob/main/docs/QUICKSTART.md), [developer lifecycle](https://github.com/jesseglab/notchwork/blob/main/docs/DEVELOPERS.md), and [LLM prompts](https://github.com/jesseglab/notchwork/blob/main/docs/LLM_PROMPTS.md). Use your own stable source and activity IDs. Keep domain actions in your app and validate every incoming event against your current model.

Portkeeper’s normal terminal/workspace UI remains native. Its shared-notch controls are offline HTML rendered by Notchwork; this is not a pixel-for-pixel copy of the removed native notch panels.

CI checks out a tested Notchwork revision beside Portkeeper before building. Local builds accept a sibling checkout or `NOTCHWORK_PACKAGE_PATH`. For distribution, use a tested matching SDK/runtime revision, include license notices, and follow [the distribution guide](https://github.com/jesseglab/notchwork/blob/main/docs/DISTRIBUTION.md).

## Dashboard fidelity and runtime requirement

The shared notch uses Portkeeper’s original 400 × 590 dashboard proportions, header, Services/Ports tabs, project groups, compact rows, and action placement. Live state is separate from HTML so updates preserve the tab, filter, and scroll position. The dashboard includes all normal-sized workspaces; unusually large payloads disclose overflow with a link to the full native workspace. Commands, logs, and diagnostic secrets stay in Portkeeper.

This client requires Notchwork 0.2.0 build 8 or newer for live interface state. Existing Custom UI opt-outs are preserved; the host presents an explicit Enable controls action instead of silently pretending the fallback is the app UI.

Service/project editors, listener stop confirmations, handoff tools, and terminal sessions use the existing native workspace. They are not yet embedded notch pages; the dashboard routes to the correct native page and selected service. The app still creates no independent notch window.
