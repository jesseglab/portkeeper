# Set up this project for Portkeeper

I use Portkeeper, a macOS notch app that starts, stops, and restarts local services from a JSON manifest. Please inspect **this project** and prepare a runnable `portkeeper.json` in the project root.

1. Read the repository's instructions, package scripts, local launch scripts, Docker Compose files, and relevant configuration. Identify the services needed for normal local development, including web, API, local dependencies, and any explicitly requested tunnel.
2. Do the one-time project setup that is safe and authorized in this workspace: select a compatible runtime (check `.nvmrc` and package engine requirements), install declared dependencies if needed, prepare example environment files without inventing credentials, and fix routine setup problems. Ask me for any missing secret or account access. Do not put secrets, tokens, or private environment values in the JSON.
3. Actually start each proposed command and verify its expected listening port. A successful package install or a process that stays alive without opening its port is not enough. Stop test processes before handing off so Portkeeper can own and stop them. Do not automatically publish a local service with ngrok or another tunnel unless I explicitly requested it.
4. Write **only valid JSON** (no comments or Markdown fences) to `portkeeper.json` at the repository root. Use the schema below. List services in the order they should start. Each `directory` is relative to the JSON file (`"."` means the project root). Each `command` is one long-running shell command that stays in the foreground, using the verified start command for that service. Do not use `&`, `nohup`, or a daemonizing command. Set `port` to `null` for a tunnel or process without a predictable local TCP listener. `url` is optional and should be an HTTP(S) address to open.
5. Include the JSON in your response so I can paste it into Portkeeper. For pasted JSON, prefer absolute folder paths; otherwise tell me which base folder to choose. Tell me what you set up, any prerequisites I must handle, and the JSON file path. If a service cannot run because of missing secrets, dependencies, or another blocker, explain the blocker and **leave that service out of `services`** until it is verified. Never present the JSON as fully ready while a listed service is known to fail.

This is a structural template, not a runnable example. Replace the project, service, folder, and command placeholders with verified values for the current project. Set `port` to the actual verified port, or keep it `null` when the service has no predictable listener. Add `url` only when verified. No ports or projects are preconfigured.

```json
{
  "version": 1,
  "project": "<project name>",
  "services": [
    {
      "name": "<service name>",
      "directory": "<service folder>",
      "command": "<verified foreground start command>",
      "port": null
    }
  ]
}
```

After you finish, I will choose **Paste project JSON** or **Import project JSON** in Portkeeper, review the commands, and choose **Import & Start**. Portkeeper will save the services and run them in the listed order; it will flag occupied ports rather than terminate unrelated processes.
