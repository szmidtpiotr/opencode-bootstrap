# OpenCode Machine Bootstrap

Bootstrap script to set up OpenCode on a fresh Linux machine with:

- OpenCode install
- Filtered model discovery (`Responses API` compatible + no Ollama subscription-locked models)
- `~/.config/opencode/opencode.json` generation
- `opencode-web` systemd user service on port `4096`
- Shared Web + TUI workflow helpers: `oc` and `oc-web-here`

## 1) Requirements

- Linux with `bash`, `python3`, `curl`, `systemd --user`
- Network access to Azure + Ollama endpoints
- Logged in shell user (the script writes to that user's home)

## 2) Inputs and environment variables

Installer is interactive now. If a value is missing, it asks during setup.

You can still prefill values via env vars to avoid prompts:

```bash
export KOSZYCKAKAPRYS_AZURE_API_KEY="YOUR_AZURE_KEY"
export OLLAMA_CLOUD_TOKEN="YOUR_OLLAMA_TOKEN"
export OPENCODE_PASSWORD="YOUR_WEB_PASSWORD"
```

Optional prefill:

```bash
export OPENCODE_USERNAME="piotrszmidt"
export PROJECT_DIR="$HOME"
export OPENCODE_PORT="4096"
export OPENCODE_HOSTNAME="0.0.0.0"
export OPENCODE_MDNS_DOMAIN="opencode.local"
export AZURE_RESOURCE_NAME="koszyckakaprys"
export OLLAMA_LOCAL_URL="https://api-ollama.studio-colorbox.com"
```

For Ollama on another machine in LAN, set for example:

```bash
export OLLAMA_LOCAL_URL="http://192.168.1.61:11434"
```

## 3) Run installer

```bash
chmod +x ./install-opencode-stack.sh
./install-opencode-stack.sh
```

## 4) Verify

```bash
systemctl --user status opencode-web --no-pager
opencode models ollama-cloud-free
```

## 5) Refresh model discovery after adding new models

If you add or deploy new models after installation, run discovery again:

```bash
bash ~/.config/opencode/discover-models.sh
```

This rebuilds `~/.config/opencode/opencode.json` and restarts `opencode-web`.

## 6) Daily workflow

- Start shared terminal UI in a project dir:
  ```bash
  oc
  ```
- Point web backend to current repo and restart service:
  ```bash
  oc-web-here
  ```

Web URL:

- `http://127.0.0.1:4096`

