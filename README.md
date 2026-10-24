# Portkeeper with the shared Notchwork runtime

Portkeeper owns its service state, controls, and actions. **Notchwork is a required runtime and owns all notch rendering.** Portkeeper has no independent notch or edge-panel implementation.

On first launch Portkeeper reuses a compatible installed Notchwork, or installs the verified bundled copy to `~/Applications/Notchwork.app`. It launches the runtime in the background, registers its interface, and publishes live status over the API. There is no optional status-sharing switch, file watcher, or duplicate fallback notch.

Click the Portkeeper menu-bar item to open its UI in Notchwork. Service start/stop/restart controls are supplied by Portkeeper. Project handoff, detailed management, and terminals open the normal Portkeeper workspace window.

Notchwork settings select One (one app uses the whole container), Two (fixed left/right apps), or Multiple (two visible apps selected by high/mid/low priority and newest meaningful update). Portkeeper reports issues as high, startup as mid, and healthy or idle state as low.

## Build this coordinated development version

Clone both current development branches side by side (old Notchwork 0.1.x tags do not provide API 2):

```sh
git clone https://github.com/jesseglab/notchwork.git
git clone https://github.com/jesseglab/portkeeper.git
cd portkeeper
```

Expected layout:

```text
source/
  notchwork/
  portkeeper/
```

From `portkeeper`, run `zsh build.sh`. The build uses the sibling Notchwork SDK, builds the matching runtime, and bundles it in the resulting Portkeeper app. Set `NOTCHWORK_PACKAGE_PATH` to use a different local Notchwork checkout. `NOTCHWORK_RUNTIME_APP_PATH` can point at an already-built matching runtime; it is signature-checked before bundling.

```sh
zsh Tests/run.sh
zsh build.sh
open dist/Portkeeper.app
```

No administrator permission or network download is needed for the first-run user installation. An incompatible existing destination is preserved and reported in settings; an older running runtime must be quit before the new version can take over. The app never silently falls back to a private notch renderer.

These are local development builds, not a notarized public release. See [runtime integration](docs/NOTCHWORK.md).

See [third-party notices](THIRD_PARTY_NOTICES.md) for bundled dependency licensing.

## Building your own Notchwork client

Use [Notchwork’s quickstart](https://github.com/jesseglab/notchwork/blob/main/docs/QUICKSTART.md) and [copyable LLM prompts](https://github.com/jesseglab/notchwork/blob/main/docs/LLM_PROMPTS.md). Portkeeper is a reference integration, not a required dependency for other clients.

- [Runtime installer](Sources/NotchworkRuntime.swift): verified prerequisite installation and reuse.
- [API bridge](Sources/NotchworkBridge.swift): registration, state publication, events, reconnect, and cleanup.
- [Runtime integration guide](docs/NOTCHWORK.md): ownership and priority rules.
