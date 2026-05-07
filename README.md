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

## 2) Environment variables

Set these before running:

```bash
export KOSZYCKAKAPRYS_AZURE_API_KEY="YOUR_AZURE_KEY"
export OLLAMA_CLOUD_TOKEN="YOUR_OLLAMA_TOKEN"
export OPENCODE_PASSWORD="YOUR_WEB_PASSWORD"
```

Optional:

```bash
export OPENCODE_USERNAME="piotrszmidt"
export PROJECT_DIR="$HOME/remout_mount/ai-gm"
export OPENCODE_PORT="4096"
export OPENCODE_HOSTNAME="0.0.0.0"
export OPENCODE_MDNS_DOMAIN="opencode.local"
export AZURE_RESOURCE_NAME="koszyckakaprys"
export OLLAMA_LOCAL_URL="https://api-ollama.studio-colorbox.com"
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

## 5) Daily workflow

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

