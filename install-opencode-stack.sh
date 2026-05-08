#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR_DEFAULT="${HOME}"
PROJECT_DIR="${PROJECT_DIR:-$PROJECT_DIR_DEFAULT}"
OPENCODE_PORT="${OPENCODE_PORT:-4096}"
# Bind address: konserwatywnie puste — domyślna automatycznie w prompt_config().
OPENCODE_HOSTNAME="${OPENCODE_HOSTNAME:-}"
OPENCODE_MDNS_DOMAIN="${OPENCODE_MDNS_DOMAIN:-opencode.local}"
AZURE_RESOURCE_NAME="${AZURE_RESOURCE_NAME:-koszyckakaprys}"
KOSZYCKAKAPRYS_AZURE_API_KEY="${KOSZYCKAKAPRYS_AZURE_API_KEY:-}"
OLLAMA_CLOUD_TOKEN="${OLLAMA_CLOUD_TOKEN:-}"
OLLAMA_LOCAL_URL="${OLLAMA_LOCAL_URL:-https://api-ollama.studio-colorbox.com}"

prompt_if_empty() {
  local var_name="$1"
  local prompt_text="$2"
  local secret="${3:-false}"
  local current="${!var_name}"
  local value=""

  if [[ -n "${current}" ]]; then
    return
  fi

  while true; do
    if [[ "${secret}" == "true" ]]; then
      read -r -s -p "${prompt_text}: " value
      echo
    else
      read -r -p "${prompt_text}: " value
    fi
    if [[ -n "${value}" ]]; then
      printf -v "${var_name}" "%s" "${value}"
      return
    fi
    echo "Value cannot be empty."
  done
}

prompt_with_default() {
  local var_name="$1"
  local prompt_text="$2"
  local current="${!var_name}"
  local input=""
  read -r -p "${prompt_text} [${current}]: " input
  if [[ -n "${input}" ]]; then
    printf -v "${var_name}" "%s" "${input}"
  fi
}

prompt_config() {
  echo "== OpenCode installer configuration =="
  prompt_with_default PROJECT_DIR "Project directory for web service"
  prompt_with_default OPENCODE_PORT "OpenCode port"

  local autodetected
  autodetected="$(guess_primary_ipv4 || true)"
  if [[ -z "${autodetected}" ]]; then
    autodetected="0.0.0.0"
  fi
  if [[ -z "${OPENCODE_HOSTNAME}" ]]; then
    OPENCODE_HOSTNAME="${autodetected}"
  fi

  prompt_with_default OPENCODE_HOSTNAME "Bind/IP for web (recommended: LAN IPv4 of this machine, e.g. 192.168.1.x — one origin for browsers; enter 0.0.0.0 to listen everywhere)"
  prompt_with_default OPENCODE_MDNS_DOMAIN "mDNS domain"
  prompt_with_default AZURE_RESOURCE_NAME "Azure resource name"
  prompt_with_default OLLAMA_LOCAL_URL "Ollama URL (local or LAN, eg. http://192.168.1.61:11434)"
  prompt_if_empty KOSZYCKAKAPRYS_AZURE_API_KEY "Azure API key (KOSZYCKAKAPRYS_AZURE_API_KEY)" true
  prompt_if_empty OLLAMA_CLOUD_TOKEN "Ollama Cloud token (OLLAMA_CLOUD_TOKEN)" true
}

guess_primary_ipv4() {
  ip -4 route get 1.1.1.1 2>/dev/null \
    | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }' \
    || hostname -I 2>/dev/null | awk '{ print $1; exit }'
}

normalize_ollama_local_url() {
  local url="$1"
  url="${url%/}"
  if [[ "${url}" != http://* && "${url}" != https://* ]]; then
    url="http://${url}"
  fi
  url="${url%/v1}"
  printf "%s" "${url}"
}

write_install_env() {
  mkdir -p "${HOME}/.config/opencode"
  (
    umask 077
    {
      printf 'OPENCODE_WEB_HOSTNAME=%q\n' "${OPENCODE_HOSTNAME}"
      printf 'OPENCODE_WEB_PORT=%q\n' "${OPENCODE_PORT}"
      printf 'OPENCODE_MDNS_DOMAIN=%q\n' "${OPENCODE_MDNS_DOMAIN}"
      printf 'AZURE_RESOURCE_NAME=%q\n' "${AZURE_RESOURCE_NAME}"
      printf 'OLLAMA_LOCAL_BASE=%q\n' "${OLLAMA_LOCAL_URL}"
      printf 'OPENCODE_PUBLIC_ORIGIN=%q\n' "${OC_DEFAULT_ATTACH}"
    } > "${HOME}/.config/opencode/install.env"
  )
  chmod 600 "${HOME}/.config/opencode/install.env" || true
}

install_opencode() {
  if command -v opencode >/dev/null 2>&1; then
    echo "opencode already installed: $(command -v opencode)"
    return
  fi

  echo "Installing opencode..."
  curl -fsSL "https://opencode.ai/install" | bash
  export PATH="${HOME}/.opencode/bin:${PATH}"
  command -v opencode >/dev/null 2>&1 || {
    echo "opencode installation failed." >&2
    exit 1
  }
}

write_discover_script() {
  mkdir -p "${HOME}/.config/opencode"
  cat > "${HOME}/.config/opencode/discover-models.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${HOME}/.config/opencode"
CONFIG_FILE="${CONFIG_DIR}/opencode.json"
mkdir -p "${CONFIG_DIR}"

INSTALL_ENV="${CONFIG_DIR}/install.env"
if [[ -r "${INSTALL_ENV}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${INSTALL_ENV}"
  set +a
fi

AZURE_URL="${AZURE_URL:-https://koszyckakaprys.openai.azure.com}"
OLLAMA_CLOUD_TOKEN="${OLLAMA_CLOUD_TOKEN:-}"

OLLAMA_LOCAL_URL="${OLLAMA_LOCAL_BASE:-https://api-ollama.studio-colorbox.com}"

OPENCODE_WEB_HOSTNAME="${OPENCODE_WEB_HOSTNAME:-0.0.0.0}"
OPENCODE_WEB_PORT="${OPENCODE_WEB_PORT:-4096}"
OPENCODE_MDNS_DOMAIN="${OPENCODE_MDNS_DOMAIN:-opencode.local}"
AZURE_RESOURCE_NAME="${AZURE_RESOURCE_NAME:-koszyckakaprys}"

OLLAMA_OPENAPI_BASE="${OLLAMA_LOCAL_URL%/}/v1"

prompt_secret_if_empty() {
  local var_name="$1"
  local prompt_text="$2"
  local current="${!var_name}"
  if [[ -n "${current}" ]]; then
    return
  fi
  if [[ ! -t 0 ]]; then
    echo "Missing ${var_name} and stdin is not a TTY; set it in the environment or ~/.config/opencode/install.env" >&2
    exit 1
  fi
  local value=""
  while [[ -z "${value}" ]]; do
    read -r -s -p "${prompt_text}: " value
    echo
    [[ -n "${value}" ]] || echo "Value cannot be empty."
  done
  printf -v "${var_name}" "%s" "${value}"
}

KOSZYCKAKAPRYS_AZURE_API_KEY="${KOSZYCKAKAPRYS_AZURE_API_KEY:-}"
prompt_secret_if_empty KOSZYCKAKAPRYS_AZURE_API_KEY "KOSZYCKAKAPRYS_AZURE_API_KEY"
AZURE_API_KEY="${KOSZYCKAKAPRYS_AZURE_API_KEY}"

prompt_secret_if_empty OLLAMA_CLOUD_TOKEN "OLLAMA_CLOUD_TOKEN"

echo "Discovering models..."

AZURE_DEPLOYMENTS="$(curl -sf "${AZURE_URL}/openai/deployments?api-version=2023-03-15-preview" -H "api-key: ${AZURE_API_KEY}" || echo "[]")"

AZURE_MODELS_JSON="$(echo "${AZURE_DEPLOYMENTS}" | python3 -c "
import sys, json, urllib.request, urllib.error
try:
    az_key = '${AZURE_API_KEY}'
    responses_url = '${AZURE_URL}/openai/v1/responses'
    data = json.load(sys.stdin)
    models = data.get('data', [])
    def supported_by_responses(model_id):
        payload = json.dumps({'model': model_id, 'input': 'ping', 'max_output_tokens': 16}).encode()
        req = urllib.request.Request(
            responses_url,
            data=payload,
            method='POST',
            headers={'api-key': az_key, 'Content-Type': 'application/json'},
        )
        try:
            with urllib.request.urlopen(req, timeout=20):
                return True
        except urllib.error.HTTPError as err:
            body = err.read(512).decode(errors='ignore').lower()
            if 'not supported by responses api' in body:
                return False
            return err.code not in (401, 403, 404)
        except Exception:
            return False
    filtered = []
    for model in models:
        mid = model.get('id', '')
        if not mid:
            continue
        lower = mid.lower()
        if any(x in lower for x in ['whisper', 'dall', 'image', 'audio', 'transcribe', 'tts']):
            continue
        if not supported_by_responses(mid):
            continue
        filtered.append({'id': mid, 'name': mid})
    print(json.dumps(filtered))
except Exception:
    print('[]')
" 2>/dev/null || echo "[]")"

OLLAMA_LOCAL_JSON="$(curl -sf "${OLLAMA_LOCAL_URL}/v1/models" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps([{'id': m.get('id'), 'name': m.get('id')} for m in data.get('data', []) if m.get('id')]))
except Exception:
    print('[]')
" 2>/dev/null || echo "[]")"

OLLAMA_CLOUD_JSON="$(curl -sf "https://ollama.com/v1/models" -H "Authorization: Bearer ${OLLAMA_CLOUD_TOKEN}" | python3 -c "
import sys, json, urllib.request, urllib.error
try:
    token = '${OLLAMA_CLOUD_TOKEN}'
    data = json.load(sys.stdin)
    models = data.get('data', [])
    def usable(model_id):
        payload = json.dumps({'model': model_id, 'input': 'ping', 'max_output_tokens': 16}).encode()
        req = urllib.request.Request(
            'https://ollama.com/v1/responses',
            data=payload,
            method='POST',
            headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
        )
        try:
            with urllib.request.urlopen(req, timeout=20):
                return True
        except urllib.error.HTTPError as err:
            body = err.read(512).decode(errors='ignore').lower()
            if 'requires a subscription' in body:
                return False
            return err.code not in (401, 403, 404)
        except Exception:
            return False
    result = []
    for model in models:
        mid = model.get('id', '')
        if mid and usable(mid):
            result.append({'id': mid, 'name': mid})
    print(json.dumps(result))
except Exception:
    print('[]')
" 2>/dev/null || echo "[]")"

# Encode JSON payloads to avoid shell interpolation edge cases.
AZURE_MODELS_JSON_B64="$(printf '%s' "${AZURE_MODELS_JSON}" | base64 -w0)"
OLLAMA_LOCAL_JSON_B64="$(printf '%s' "${OLLAMA_LOCAL_JSON}" | base64 -w0)"
OLLAMA_CLOUD_JSON_B64="$(printf '%s' "${OLLAMA_CLOUD_JSON}" | base64 -w0)"
export AZURE_RESOURCE_NAME AZURE_MODELS_JSON_B64 OLLAMA_LOCAL_JSON_B64 OLLAMA_CLOUD_JSON_B64 CONFIG_FILE
export OPENCODE_PUBLIC_ORIGIN="${OPENCODE_PUBLIC_ORIGIN:-}"
export OPENCODE_WEB_HOSTNAME OPENCODE_WEB_PORT OPENCODE_MDNS_DOMAIN
export OLLAMA_OPENAPI_BASE OLLAMA_CLOUD_TOKEN

python3 - <<'PY'
import base64
import json
import os

def decode_json(env_name):
    raw = base64.b64decode(os.environ[env_name]).decode("utf-8")
    return json.loads(raw)

azure_models = decode_json("AZURE_MODELS_JSON_B64")
ollama_local = decode_json("OLLAMA_LOCAL_JSON_B64")
ollama_cloud = decode_json("OLLAMA_CLOUD_JSON_B64")

def to_map(items):
    out = {}
    for item in items:
        model_id = item.get('id')
        model_name = item.get('name')
        if model_id and model_name:
            out[model_id] = {'name': model_name}
    return out

res_name = os.environ["AZURE_RESOURCE_NAME"]

def cors_origins():
    port = int(os.environ["OPENCODE_WEB_PORT"])
    hn = os.environ.get("OPENCODE_WEB_HOSTNAME", "0.0.0.0")
    pub = (os.environ.get("OPENCODE_PUBLIC_ORIGIN") or "").strip().rstrip("/")
    out = [
        "http://127.0.0.1:{}".format(port),
        "http://localhost:{}".format(port),
    ]
    if pub and pub not in out:
        out.append(pub)
    if hn and hn not in ("", "0.0.0.0"):
        lan = "http://{}:{}".format(hn, port)
        if lan not in out:
            out.append(lan)
    return out

config = {
    "$schema": "https://opencode.ai/config.json",
    "model": "azure-koszycka/gpt-5.4",
    "small_model": "azure-koszycka/gpt-4.1",
    "server": {
        "port": int(os.environ["OPENCODE_WEB_PORT"]),
        "hostname": os.environ["OPENCODE_WEB_HOSTNAME"],
        "mdns": True,
        "mdnsDomain": os.environ["OPENCODE_MDNS_DOMAIN"],
        "cors": cors_origins(),
    },
    "provider": {
        "azure-koszycka": {
            "npm": "@ai-sdk/azure",
            "name": "Azure ({})".format(res_name),
            "options": {
                "resourceName": res_name,
                "apiKey": "{env:KOSZYCKAKAPRYS_AZURE_API_KEY}",
                "useCompletionUrls": True
            },
            "models": to_map(azure_models)
        },
        "ollama-local": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "Ollama (Local)",
            "options": {
                "baseURL": os.environ["OLLAMA_OPENAPI_BASE"],
            },
            "models": to_map(ollama_local)
        },
        "ollama-cloud-free": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "Ollama Cloud (Free usable)",
            "options": {
                "baseURL": "https://ollama.com/v1",
                "apiKey": os.environ["OLLAMA_CLOUD_TOKEN"],
            },
            "models": to_map(ollama_cloud)
        }
    }
}

with open(os.environ["CONFIG_FILE"], "w", encoding="utf-8") as fh:
    json.dump(config, fh, indent=2)
print(f"Saved {os.environ['CONFIG_FILE']}")
print(f"Azure models: {len(azure_models)} | Ollama local: {len(ollama_local)} | Ollama cloud free: {len(ollama_cloud)}")
PY
EOF
  chmod +x "${HOME}/.config/opencode/discover-models.sh"
}

write_service_files() {
  mkdir -p "${HOME}/.config/systemd/user/opencode-web.service.d"
  cat > "${HOME}/.config/systemd/user/opencode-web.service" <<EOF
[Unit]
Description=OpenCode Web Server
After=network.target

[Service]
Type=simple
ExecStart=${HOME}/.opencode/bin/opencode web --hostname ${OPENCODE_HOSTNAME} --port ${OPENCODE_PORT} --mdns --mdns-domain ${OPENCODE_MDNS_DOMAIN}
Restart=always
RestartSec=5
Environment=HOME=${HOME}
Environment=PATH=${HOME}/.opencode/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=KOSZYCKAKAPRYS_AZURE_API_KEY=${KOSZYCKAKAPRYS_AZURE_API_KEY}
Environment=OLLAMA_CLOUD_TOKEN=${OLLAMA_CLOUD_TOKEN}
Environment=OPENCODE_DISABLE_MODELS_FETCH=true

[Install]
WantedBy=default.target
EOF

  cat > "${HOME}/.config/systemd/user/opencode-web.service.d/override.conf" <<EOF
[Service]
UnsetEnvironment=OPENCODE_SERVER_USERNAME OPENCODE_SERVER_PASSWORD
WorkingDirectory=${PROJECT_DIR}
EOF
}

write_helpers() {
  mkdir -p "${HOME}/.local/bin"

  cat > "${HOME}/.local/bin/oc" <<'OCO'
#!/usr/bin/env bash
set -euo pipefail

INSTALL_ENV="${HOME}/.config/opencode/install.env"

canonical_opencode_web_url() {
  local bind="" port="4096"
  if [[ -r "${INSTALL_ENV}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${INSTALL_ENV}"
    set +a
  fi
  bind="${OPENCODE_WEB_HOSTNAME:-}"
  port="${OPENCODE_WEB_PORT:-4096}"
  if [[ -z "${bind}" || "${bind}" == "0.0.0.0" ]]; then
    bind="$(ip -4 route get 1.1.1.1 2>/dev/null \
      | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }')"
    [[ -z "${bind}" ]] && bind="$(hostname -I 2>/dev/null | awk '{ print $1; exit }')"
    [[ -z "${bind}" ]] && bind="127.0.0.1"
  fi
  printf 'http://%s:%s' "${bind}" "${port}"
}

SERVER_URL="${OPENCODE_ATTACH_URL:-$(canonical_opencode_web_url)}"
REMOTE_DIR="${PWD}"
exec "${HOME}/.opencode/bin/opencode" attach "${SERVER_URL}" --dir "${REMOTE_DIR}" "$@"
OCO

  cat > "${HOME}/.local/bin/oc-web-here" <<'OCH'
#!/usr/bin/env bash
set -euo pipefail

INSTALL_ENV="${HOME}/.config/opencode/install.env"

canonical_opencode_web_url() {
  local bind="" port="4096"
  if [[ -r "${INSTALL_ENV}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${INSTALL_ENV}"
    set +a
  fi
  bind="${OPENCODE_WEB_HOSTNAME:-}"
  port="${OPENCODE_WEB_PORT:-4096}"
  if [[ -z "${bind}" || "${bind}" == "0.0.0.0" ]]; then
    bind="$(ip -4 route get 1.1.1.1 2>/dev/null \
      | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }')"
    [[ -z "${bind}" ]] && bind="$(hostname -I 2>/dev/null | awk '{ print $1; exit }')"
    [[ -z "${bind}" ]] && bind="127.0.0.1"
  fi
  printf 'http://%s:%s' "${bind}" "${port}"
}

if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  target_dir="${git_root}"
else
  target_dir="${PWD}"
fi

override_dir="${HOME}/.config/systemd/user/opencode-web.service.d"
override_file="${override_dir}/override.conf"
mkdir -p "${override_dir}"

cat > "${override_file}" <<EOT
[Service]
UnsetEnvironment=OPENCODE_SERVER_USERNAME OPENCODE_SERVER_PASSWORD
WorkingDirectory=${target_dir}
EOT

systemctl --user daemon-reload
systemctl --user restart opencode-web
sleep 2

if systemctl --user is-active opencode-web >/dev/null 2>&1; then
  echo "opencode-web now serves: ${target_dir}"
  printf '%s\n' "Canonical web UI: $(canonical_opencode_web_url)"
else
  echo "opencode-web failed to start for ${target_dir}" >&2
  systemctl --user status opencode-web --no-pager >&2 || true
  exit 1
fi
OCH

  chmod +x "${HOME}/.local/bin/oc" "${HOME}/.local/bin/oc-web-here"
}

ensure_local_bin_in_path() {
  if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "${HOME}/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${HOME}/.bashrc"
  fi
}

main() {
  prompt_config
  OLLAMA_LOCAL_URL="$(normalize_ollama_local_url "${OLLAMA_LOCAL_URL}")"

  if [[ "${OPENCODE_HOSTNAME}" == "0.0.0.0" ]]; then
    CANON_HOST="$(guess_primary_ipv4 || true)"
    [[ -z "${CANON_HOST}" ]] && CANON_HOST="127.0.0.1"
  else
    CANON_HOST="${OPENCODE_HOSTNAME}"
  fi
  OC_DEFAULT_ATTACH="http://${CANON_HOST}:${OPENCODE_PORT}"

  install_opencode
  write_install_env
  write_discover_script
  write_service_files

  write_helpers
  ensure_local_bin_in_path

  export AZURE_RESOURCE_NAME KOSZYCKAKAPRYS_AZURE_API_KEY OLLAMA_CLOUD_TOKEN OLLAMA_LOCAL_URL
  export OPENCODE_PORT OPENCODE_HOSTNAME OPENCODE_MDNS_DOMAIN
  "${HOME}/.config/opencode/discover-models.sh"

  systemctl --user daemon-reload
  systemctl --user enable --now opencode-web
  systemctl --user restart opencode-web

  echo
  echo "Done."
  echo "Canonical web UI: ${OC_DEFAULT_ATTACH}"
  echo "CLI default attach targets that URL unless OPENCODE_ATTACH_URL overrides it."
  echo "Use in project dir: oc"
  echo "Switch web project: oc-web-here"
}

main "$@"
