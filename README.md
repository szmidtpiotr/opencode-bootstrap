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
```

Optional prefill:

```bash
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

### Bind address, `install.env`, and canonical URL

The installer prompts for **Bind/IP for web** (with an autodetected LAN IPv4 as the default suggestion). Typical choice is this machine’s address on your LAN (e.g. `192.168.1.170`), so browsers and helpers use a single predictable origin.

- **`0.0.0.0`** — listen on all interfaces. **`oc`**, **`oc-web-here`**, and the installer summary still print a **canonical URL using your current LAN IPv4** (read from `install.env` plus route lookup), so it matches what other machines use on the LAN.
- **Specific IP in `install.env`** — that exact host is used in the printed URL (no extra lookup).

Web UI HTTP basic auth is **not** configured by this bootstrap. Do **not** put **`OPENCODE_SERVER_USERNAME`** / **`OPENCODE_SERVER_PASSWORD`** in `~/.profile` or `~/.bashrc`: on many desktops **`systemctl --user`** imports that login environment, so OpenCode would still see them even if they are absent from the unit file. The installer adds **`UnsetEnvironment=…`** in **`opencode-web.service.d/override.conf`** so those vars are dropped for the service.

If **`AZURE_RESOURCE_NAME`** is exported in your login shell, **`systemctl --user`** may import it and OpenCode will also load the **built-in Azure** catalog (a duplicate next to **`azure-koszycka`**). The bootstrap sets **`enabled_providers`** in **`opencode.json`** to only **`azure-koszycka`**, **`ollama-local`**, and **`ollama-cloud-free`**, and drops **`AZURE_RESOURCE_NAME`** in the **`opencode-web`** overrides via **`UnsetEnvironment`**.

Discovery writes **`OPENCODE_PUBLIC_ORIGIN`** into **`install.env`** (canonical browser URL, e.g. `http://192.168.1.170:4097`) and sets **`server.cors`** in **`opencode.json`** so the SPA can call the API from that origin instead of behaving like a lone `localhost` session.

Persistent settings in **`~/.config/opencode/install.env`** include: `OPENCODE_WEB_HOSTNAME`, `OPENCODE_WEB_PORT`, `OPENCODE_MDNS_DOMAIN`, `AZURE_RESOURCE_NAME`, `OLLAMA_LOCAL_BASE`, `OPENCODE_PUBLIC_ORIGIN`. **`~/.config/opencode/discover-models.sh`** sources that file before regenerating **`opencode.json`**. If **`KOSZYCKAKAPRYS_AZURE_API_KEY`** or **`OLLAMA_CLOUD_TOKEN`** are missing and you run discovery **interactively**, the script **prompts** for them; from cron/non-TTY it exits with a clear error unless the variables are set.

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

This rebuilds `~/.config/opencode/opencode.json`. Restart the service if needed:

```bash
systemctl --user restart opencode-web
```

**Ollama Cloud list empty in the UI?** Discovery probes each cloud model against `/v1/responses`; if that probe yields no models (rate limits, API changes) but `https://ollama.com/v1/models` still returns a catalog, the script **falls back** to that catalog (capped) so the provider is not empty. Ensure **`OLLAMA_CLOUD_TOKEN`** is set when you run discovery (`Environment` from `opencode-web`, or export in the shell).

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

- Use the **canonical URL** printed at the end of the installer or by **`oc-web-here`** (same logic as **`oc`** default attach). Port comes from **`OPENCODE_WEB_PORT`** in `install.env`.
- Override the CLI attach target: `export OPENCODE_ATTACH_URL="http://…"`.

