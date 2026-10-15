# Preview validation

15 October 2026 · Portkeeper 1.3, build 7 · Apple silicon

- 119 checks pass against the actual NotchworkKit dependency, including native motion, terminal input, restart, diagnostics, Porty, and output handling.
- Custom-interface callbacks validate sharing permission, known service identity, and supported actions. Start/stop tests run a real temporary managed process.
- Status snapshots validate against the typed Notchwork API and include Portkeeper’s own panel without exporting logs or commands.
- The release build links NotchworkKit statically and bundles its LICENSE and NOTICE.
- The README cover is an original vector illustration, exported to PNG. It is not an application screenshot. The small Porty image is a resized copy of the existing app icon.
- The dependency is pinned to Notchwork 0.1.0. The release build resolves the published Git tag; an explicit local checkout override remains available for SDK development.
- The installed Portkeeper app has not been replaced or restarted. Publishing does not install the update locally.
- Ad-hoc signatures only. Developer ID signing and notarization remain outside scope.

## Release privacy

- A fresh profile has no services, logs, or enabled sharing preference; this is covered by the test suite.
- The handoff template has no fixed ports, folders, or commands. Optional preview services use explicitly synthetic fixtures.
- Source and the built app pass `python3 scripts/check-release-privacy.py`. The build rejects local configuration files, log files, and absolute home-directory paths. This is a targeted release guard, not a general secret scanner.
- Git history was reviewed for bundled user configuration and private project paths. Only generic example ports and commands appeared in the prior published version; those examples have been removed from the prepared update.
