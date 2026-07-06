# Self-Hosted OpenCode Context

This OpenCode instance is self-hosted on **Coolify** inside a Docker container. The following rules apply to every session.

## Runtime environment

- You are running inside a **Docker container** on a host managed by **Coolify**.
- The host system is **not yours**. Do not run commands against the host, against the Docker daemon, or against other Coolify services.
- The container's writable, persistent areas are:
  - `/projects` — user projects. This is your **working directory**.
  - `/opencode` — OpenCode session DB, snapshots, repos, and config. Treat as persistent.
- Everything **outside** `/projects` and `/opencode` (including `/root`, `/opt`, `/usr`, `/etc`, `/tmp`) is **ephemeral**: it is rebuilt on every container start or image update. Do not write to it.

## Hard rules

- **Do not run local Docker builds, tests, or any command that requires the host Docker daemon.** Ask the user to deploy and share the results with you instead.
- **Do not pollute the host or container system.** Keep all edits inside `/projects`. Never write source files, dependencies, or build artifacts outside `/projects`.
- **Do not modify image-shipped files** (under `/usr/local/bin`, `/opt/opencode-seed`, `/etc`). If you need different system-level config, ask the user to change it via environment variables, the `/opencode/config` volume, or a redeploy.
- **Do not run `apt`, `npm install -g`, or other package installs** that mutate the container. If a tool is missing, ask the user to add it to the Dockerfile and redeploy.
- **SSH operations are scoped to GitHub only.** The ssh-agent at startup is configured for `github.com`. Do not use it for other hosts.

## Working with the user

- The user is the operator. They deploy via Coolify and read your results in a browser (Cloudflare Tunnel, HTTP Basic Auth via `OPENCODE_SERVER_PASSWORD`).
- When you need verification of a deploy, a network call, or anything that requires real I/O against the host or the internet, **ask the user to run it and paste the output back**. Do not attempt it yourself.
- Prefer small, reviewable diffs over large rewrites. The user can `git diff` and re-deploy easily.
