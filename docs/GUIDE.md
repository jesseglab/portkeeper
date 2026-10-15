# Portkeeper

Portkeeper lives around the MacBook notch: a black surface, green monospace text, and Porty, the green blob mascot. Hover to expand your projects and ports. The left count shows active managed services; Porty reacts when a startup error, unhealthy service, or port-scan issue needs attention. AI diagnostic prompts and notifications remain available.

On displays without a camera notch, Portkeeper uses a small top-center tab. A menu-bar shortcut opens the same panel. The panels follow display configuration changes, appear across Spaces, and reduce animation when macOS Reduce Motion is enabled.

## Porty

The app icon uses Porty with larger eyes. A compact native rendition replaces the lighthouse beside the camera housing and appears in the terminal handle:

- **Idle:** relaxed eyes and a quieter green body.
- **Starting or restarting:** an upward gaze and a gentle pulse.
- **Running:** open eyes and a smile; recovery gets one short settling reaction.
- **Error or scan issue:** wide eyes, a concerned mouth, and a soft attention pulse. Errors take priority over startup and healthy services.

Visible Porty faces blink occasionally, about every 4.5–7.5 seconds. Eye movement and status reactions use small Core Animation layers, with no per-frame app timer or sprite decoding. Hidden or inactive copies stop their animation and blink timer. Reduce Motion preserves the status expressions without animated blinking, pulsing, or settling. The control's accessible description also states the current status. AI diagnostic prompts and notifications remain available.

## Motion

The notch and terminal drawer morph from their compact shapes with curved shoulders and gently damped easing. Hover reversals preserve momentum; content fades and slides into place without scaling terminal text. Page changes crossfade, buttons soften on press, and Porty softly pulses when attention is needed.

Motion follows the display refresh rate, requesting up to 120 Hz where supported, with consistent timing at 60 Hz. During expansion, the window canvas stays stationary while its shape changes; transparent areas pass clicks through. The animation driver stops at rest. macOS Reduce Motion switches the surfaces immediately and disables movement in button and page transitions, including when enabled during an animation.

## Keeping resource use low

Hover handling is event-driven; there is no continuous mouse-position poll. Surface animation runs only during transitions, and the alert pulse runs only while an issue needs attention. Collapsed content is detached from its window to avoid rendering hidden terminals, while retaining its view state.

Service output is delivered in batches up to ten times per second per service, independently of the display-synchronized surface animation. Pipe intake is bounded to 160 KB per service, and the existing 40,000-character recent-output window is retained. Under extreme output floods, older pending output is discarded in favor of the latest output. Log snapshots are coalesced on a background utility queue, with pending snapshots flushed on normal quit. Diagnostics are cached until output changes, and automatic port scans cannot overlap.

`zsh Tests/run.sh --build-only`, followed by `dist/TerminalTests.app/Contents/MacOS/TerminalTests --performance`, runs an isolated release-mode CPU/responsiveness probe with two temporary output streams. It reports app CPU, peak RSS, and main-thread scheduling gaps; it excludes automatic port scans and the child processes' CPU. Results depend on hardware and system load and are not a frame-rate guarantee.

## Projects and JSON handoff

- Start, stop, or **Restart project** from its header or actions menu. Services also have their own restart action.
- Restart first requests a graceful stop of the project's managed processes and waits for their process groups to exit. It then starts services in saved order, rescanning ports before each launch. It never kills unrelated listeners. A process that will not stop produces an error instead of a duplicate launch.
- **Project handoff → Paste project JSON** accepts JSON directly, including a Markdown JSON code block. Relative service directories require choosing a base folder; absolute paths need no base folder. File imports continue to resolve paths relative to the file.
- Both import methods validate the manifest and show the existing command review before **Import only** or **Import & Start**. Pasting alone never executes commands.
- Copy or save the included Markdown brief to have a coding assistant prepare the handoff.

## Active terminals at the right edge

Choose the sidebar icon beside a service, or **Make terminal active** in its actions. A small black tab appears halfway down the right edge. Hover or click it to slide open the terminal drawer.

- Choose services with **Add**, or select all running services. This selects output to watch; it does not start commands.
- Group by project or status; filter by name, command, port, or status. Selected stopped and failed services remain available for inspecting their final output.
- Each terminal has searchable output and **All lines / Errors / Warnings / Inputs** categories, wrapping, follow/pause, text selection, and copy.
- The `stdin >` field sends one line to the running service after its shell setup is ready. Input is limited to 511 UTF-8 bytes and recorded with common credential assignments redacted. The service must support standard input. These are service consoles, not PTY shells: full-screen tools, interactive password prompts, and Terminal/iTerm attachment are not supported.
- The terminal actions menu includes restart, start/stop, and the existing redacted AI diagnostic prompt.
- Escape or the close button collapses a panel. Moving away collapses the drawer after a short delay; editing an input keeps it open. The top panel can be pinned and stays open while editing or reviewing a handoff.
- The expand button opens the existing resizable terminal workspace, with its saved pins, density, colors, grouping, and separate windows.

Selecting or removing a terminal never stops its service. Quitting Portkeeper still stops managed services.

## Build and data

Requires Apple Silicon and macOS 14 or later. Run `zsh build.sh` to create the ad-hoc signed `dist/Portkeeper.app` and `dist/Portkeeper.zip`. Move the app to Applications and launch it. It starts no services automatically.

Service configurations and logs remain in `~/Library/Application Support/Portkeeper/`. Existing configurations and workspace preferences remain compatible. Edge terminal selections are stored separately in preferences. No project data or credentials are bundled into the app or source archive.

## Verification

Run `zsh Tests/run.sh` in a graphical Mac login session. The suite covers existing terminal behaviors, pasted manifests, screen geometry, saved edge selections, real process input, project restart, repeated restart clicks, cancellation, and native panel mounting. Motion checks cover refresh-rate independence, momentum-preserving reversals, native intermediate frames, first-open drawer animation, click-through areas, and the Reduced Motion path. Temporary services and isolated preferences are used; the test runner deliberately skips personal shell profiles.

`zsh Tests/run.sh --preview` opens the notch and drawer with sample services. Quit the preview to stop them. `--build-only` compiles the test app without opening it.

## Notchwork dependency and shared mode

See the [current README](../README.md#one-app-two-homes) for SDK builds and shared-host controls. The native surface engine is supplied by NotchworkKit. The standalone host remains optional.
