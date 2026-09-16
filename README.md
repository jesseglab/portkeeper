# Portkeeper

Portkeeper is a macOS menu bar app for local development services. It shows listening TCP ports, starts and stops commands in project folders, flags port conflicts and startup errors, and can copy a diagnostic prompt for Codex or Cursor. The menu bar lighthouse lights up while a managed service is active and blinks when an issue needs attention. Notifications open the same anchored panel, focused on the affected service or port scan.

You can add services manually or import a `portkeeper.json` prepared for a project using the included Markdown brief. Services are grouped into projects that you can rename or delete. Editing, viewing output, confirming a stop, and reviewing imported commands all happen inside the resizing menu bar panel.

Its [visual identity](IDENTITY.md) is built around a harbour lighthouse: a calm signal for the local ports the app watches.

## Build

On an Apple Silicon Mac running macOS 14 or later, run:

```sh
zsh build.sh
```

The ad-hoc signed app is packaged as `dist/Portkeeper.zip`. Extract it, move `Portkeeper.app` to Applications, and open it. macOS may ask you to approve notifications when you want startup-error alerts.

The app starts with no services. Add a command with its project folder and optional expected port, or open **Project handoff** and choose **Copy Markdown brief**. Paste the brief into your coding assistant for that project, then import the resulting `portkeeper.json` after reviewing its commands. Portkeeper does not include preset projects or credentials.

## Local data

Service configurations and output logs are stored only on your Mac in `~/Library/Application Support/Portkeeper/`. They are never copied into this repository or the build ZIP. Treat any `portkeeper.json` made for a private project as local data; the repository ignores it by default.

Portkeeper runs the shell commands you choose in their project folders. Inspect a project-import preview before choosing **Import & Start**. Stopping a listener sends a graceful termination request to its process.
