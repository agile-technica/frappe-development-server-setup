---
name: frappe-docker-dev-wizard
description: Use when continuing, refactoring, or extending this repo's Frappe Docker development setup wizard, including Bash wizard flow, DOS/shareware splash styling, Docker Compose env generation, port/subnet detection, and safe onboarding behavior.
---

# Frappe Docker Dev Wizard

Use this skill when working on `setup-frappe-dev.sh`, the README setup flow, or related Docker onboarding scripts in this repo.

## Repo Context

- The repo provisions local Frappe development stacks through `docker-compose.yml`, `.env` templates, and versioned bench startup scripts.
- `setup-frappe-dev.sh` is the host-side onboarding wizard. It should stay lean: create env/workspace, start Compose, show the startup command, then enter the Frappe container.
- The heavy Frappe/bench setup lives in `frappe-startup-scripts/frappe-bench-startup-v12.sh` through `frappe-startup-scripts/frappe-bench-startup-v16.sh` on the host, while Compose mounts them into `/workspace/frappe-bench-startup-v*.sh` inside the container.
- Generated project artifacts may exist locally, such as `.env.<project>` and `<project>-docker/`. Treat them as user/test output and do not delete them unless explicitly asked.

## Wizard Behavior To Preserve

- Keyboard-only Bash script with no required external UI packages like `dialog` or `whiptail`.
- DOS/shareware feel: colored bordered panels, blue header, magenta divider, starfield, and short startup animation.
- Splash branding intentionally credits `By: Agile Technica` and `www.agiletechnica.com`, but setup docs and SSH examples should remain generic/public.
- The splash wordmark should evoke old shareware art with a handcrafted red `FRAPPE` where letters grow across the word from smaller `F` to larger `E`; do not copy Apogee's actual logo.
- Splash should stay optional-safe:
  - Skip animation delays in non-interactive/piped output.
  - Respect `NO_COLOR=1` with readable plain-text output.
  - Respect `NO_CLEAR=1`; screen clearing should only happen for interactive terminals.
  - Respect `NO_SOUND=1`.
  - Sound is best-effort only; never fail setup if sound cannot play.
- Default Frappe version is v16, but v12-v16 remain selectable.
- Compose command detection should prefer `docker compose` and fall back to `docker-compose`.
- Env generation should derive from `.env` and write `.env.<project>`.
- Workspace creation should make `<project>-docker/` and `<project>-docker/mariadb-backup/`.
- Before starting containers, detect the Compose-managed MariaDB volume. If it exists, default to keeping it, but offer an explicit destructive reset for failed or repeated bench initialization cases.
- SSH key copy is optional. Suggest readable host keys from `~/.ssh`, allow a custom private-key path, or allow skip. Copy only into the Frappe container after Compose starts.
- SSH key discovery/custom paths should work for Linux paths, WSL-mounted Windows profile paths, and Git Bash-style Windows profile paths where practical.
- SSH host config is optional, universal, and custom-only. Do not bake company-specific presets into the wizard.
- Do not silently overwrite existing env/workspace paths; require confirmation.
- After `docker compose up -d`, show `source frappe-bench-startup-v<version>.sh`, then enter `frappe-<project>`.

## Networking Rules

- Reserve six Frappe ports and map each host port to the identical container port.
- Reserve six Socket.IO ports and map each host port to the identical container port.
- Pass all four port-range values into the Frappe container. Bench must use the
  selected Frappe and Socket.IO start ports as its internal listener ports.
- Auto-detect should skip ports already listening on the host or published by Docker.
- Prefer starts near `8000` and `9000`, then scan upward in predictable ranges.
- `PROJECT_IP_NUMBER` must be `0-255` and should avoid existing Docker networks using `10.88.<n>.0/24`.
- Warn if manually chosen ports/subnet appear occupied, but allow intentional override after confirmation.

## Bench Runtime Rules

- Keep the heavy bootstrap behavior in the versioned startup scripts and their
  shared helper; do not move it into the host-side wizard.
- Validate `FRAPPE_PORT_START`, `FRAPPE_PORT_END`, `SOCKETIO_PORT_START`, and
  `SOCKETIO_PORT_END` before installing dependencies.
- Set global Bench `webserver_port` and `socketio_port` from the selected range
  starts on every fresh or resumed run.
- Generate the Procfile web command with the selected Frappe start port.
- Load `$HOME/.nvm/nvm.sh` before resolving or running Node. Never hardcode a
  versioned NVM path in the Procfile; write the absolute result of
  `command -v node` after the versioned script selects Node.
- Re-sourcing a startup script must skip an existing valid Bench and site.
- If the persisted `env/bin/python` is missing, broken, or has a different
  major/minor version, replace only `frappe-bench/env`, reinstall requirements,
  and restore the previous environment if rebuilding fails.
- Runtime recovery must preserve apps, sites, custom code, workspace content,
  site configuration, and MariaDB data.

## Styling Guidance

- Keep the wizard fun, but setup clarity wins.
- Use ASCII-safe text for persisted files unless the existing script section intentionally uses terminal block characters for the splash.
- Avoid adding brand/logo image dependencies; terminal rendering should be self-contained.
- If making splash art bigger or more animated, keep it within a normal terminal width around 80 columns.
- Keep plain/no-color output readable and free of escape-code noise.
- Keep cancel guidance simple: tell users they can press `Ctrl-C`; do not add a separate cancel menu unless there is a real need.
- Main wizard steps should feel screen-by-screen in an interactive terminal, while non-interactive output should remain log-friendly and scroll normally.

## Sound Guidance

- Terminal BEL is unreliable in modern terminals.
- In WSL/Windows Terminal, prefer `powershell.exe` and a generated temporary WAV played through Windows audio.
- On Linux/macOS, sound should remain best-effort. Falling back to BEL is acceptable unless a portable tool is already present.
- Never require audio tools for the wizard to function.

## SSH Key Guidance

- Detect common private keys such as `id_ed25519`, `id_rsa`, `id_ecdsa`, `id_dsa`, plus readable `~/.ssh/id_*` files.
- On WSL/Windows, also check the Windows user profile `.ssh` directory when it can be resolved through `powershell.exe`, `/mnt/<drive>`, or `/<drive>`.
- In WSL, offer both WSL/Linux keys and Windows user keys when both exist, and label the source clearly in the menu.
- Custom paths may be Linux paths or Windows drive paths like `C:\Users\name\.ssh\id_ed25519`; normalize them before checking readability.
- Exclude `.pub` and `*-cert.pub` files from private-key choices.
- If `<key>.pub` exists, copy it too.
- Install keys under `/home/frappe/.ssh/` in the Frappe container.
- Set ownership to `frappe:frappe`, private key mode `600`, public key mode `644`, and `.ssh` mode `700`.
- If the user opts into SSH host config, prompt for `Host`, `HostName`, and `Port`; default `HostName` to `Host`, default `Port` to `22`, set `IdentityFile` to the copied container key, and always write `IdentitiesOnly yes`.
- Write SSH config only to `/home/frappe/.ssh/config` in the Frappe container using a managed block per host alias so reruns update instead of duplicating.
- Do not copy SSH keys into MariaDB or Redis containers.
- Do not print key contents.

## MariaDB Volume Guidance

- The Compose volume is named from the rendered Compose project plus `_mysql_vol`, for example `fdc_dev_mysql_vol`.
- If the volume exists, warn that old MariaDB data can cause rerun errors such as `Database erpnext already exists` or `Access denied for user erpnext`.
- Default to keeping existing MariaDB data.
- Only reset after explicit user confirmation.
- Reset should run `docker compose --env-file "$env_path" down`, then remove only the detected MariaDB volume.
- Do not delete the workspace, env file, SSH keys, app code, or unrelated Docker volumes.

## Validation Checklist

Run the checks that match the change:

```bash
bash -n setup-frappe-dev.sh frappe-startup-scripts/*.sh tests/test-startup-common.sh
```

```bash
bash tests/test-startup-common.sh
```

```bash
printf 'codex-test\n\n1\nN\n' | NO_COLOR=1 ./setup-frappe-dev.sh
```

```bash
FRAPPE_PORT_START=8060 FRAPPE_PORT_END=8065 \
SOCKETIO_PORT_START=9060 SOCKETIO_PORT_END=9065 \
docker compose --env-file ./.env config
```

If available:

```bash
shellcheck setup-frappe-dev.sh frappe-startup-scripts/*.sh tests/test-startup-common.sh
```

For behavior changes, manually verify:

- Invalid project names are rejected.
- Existing `.env.<project>` or `<project>-docker/` prompts before reuse/overwrite.
- Existing MariaDB volume detection defaults to keep and can be explicitly reset.
- SSH key selection can pick a discovered key, accept a custom path, or skip.
- SSH host config can be skipped or configured with a custom host/hostname/port.
- `NO_COLOR=1` output stays readable.
- `NO_SOUND=1` suppresses sound.
- Non-interactive/piped runs do not sleep for the splash animation.
- Compose config no longer references missing unversioned `frappe-bench-startup.sh`.
- Compose publishes `8060-8065` to container `8060-8065` and `9060-9065` to
  container `9060-9065`, and passes all four values into the Frappe service.
- Procfile generation preserves worker/watch/scheduler entries while replacing
  web and Socket.IO commands.
- A broken or mismatched Bench Python environment is rebuilt without changing
  apps or sites; a compatible environment is retained.
- The startup helper reports a clear error when Node remains unavailable after
  loading NVM.
