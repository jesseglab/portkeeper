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

Portkeeper owns UI content and executes only declared service/project actions. The shared container handles placement, motion, priority, and expiry. The dashboard preserves command subtitles. Explicit editor/output pages send the selected configuration or recent output to the local renderer. These fields are never execution instructions to the host or external network resources.

## Reuse this pattern in your app

Start from [the generic quickstart](https://github.com/jesseglab/notchwork/blob/main/docs/QUICKSTART.md), [developer lifecycle](https://github.com/jesseglab/notchwork/blob/main/docs/DEVELOPERS.md), and [LLM prompts](https://github.com/jesseglab/notchwork/blob/main/docs/LLM_PROMPTS.md). Use your own stable source and activity IDs. Keep domain actions in your app and validate every incoming event against your current model.

Portkeeper’s normal terminal/workspace UI remains native. Its notch pages are app-owned offline HTML rendered by Notchwork, using the original page dimensions, typography, colors, labels, and operations.

CI checks out a tested Notchwork revision beside Portkeeper before building. Local builds accept a sibling checkout or `NOTCHWORK_PACKAGE_PATH`. For distribution, use a tested matching SDK/runtime revision, include license notices, and follow [the distribution guide](https://github.com/jesseglab/notchwork/blob/main/docs/DISTRIBUTION.md).

## Dashboard fidelity and runtime requirement

The shared notch uses Portkeeper’s original 400 × 590 dashboard proportions, header, Services/Ports tabs, project groups, compact rows, and action placement. Live state is separate from HTML so updates preserve the tab, filter, and scroll position. Drafts are stored in Portkeeper and included with submissions; each page has a token that rejects stale clicks. Native file dialogs and clipboard access run in Portkeeper.

This client requires Notchwork 0.2.1 build 10 or newer, with the `interface-forms`, `side-hover`, and `user-controlled-pinning` capabilities. Existing Custom UI opt-outs are preserved; the host presents an explicit Enable controls action instead of silently pretending the fallback is the app UI.

Service/project editors and deletion confirmations, listener stop confirmation/results, handoff copy/save/paste/file import, import review, settings, output search/filter/wrap/copy/follow, and active terminal input render inside the notch. Moving the pointer away collapses these pages unless the user pins the container. Drafts stay in Portkeeper; the client does not force the notch to remain open. The ordinary terminal workspace is opened only by explicit workspace/pin/pop-out actions. The app creates no independent notch window.

Project JSON uses the same 1 MB parser limit, relative-folder resolution, validation, and review-before-import path as the native workspace. Save and import events carry the latest fields; token changes prevent repeated confirmations from executing twice. User-disabled Custom UI remains disabled. Tests exercise both app handlers and real WebKit navigation, focus, cancellation, and review.
