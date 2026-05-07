#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR_DEFAULT="${HOME}"
PROJECT_DIR="${PROJECT_DIR:-$PROJECT_DIR_DEFAULT}"
OPENCODE_PORT="${OPENCODE_PORT:-4096}"
OPENCODE_HOSTNAME="${OPENCODE_HOSTNAME:-0.0.0.0}"
OPENCODE_MDNS_DOMAIN="${OPENCODE_MDNS_DOMAIN:-opencode.local}"
OPENCODE_USERNAME="${OPENCODE_USERNAME:-$(whoami)}"
OPENCODE_PASSWORD="${OPENCODE_PASSWORD:-}"
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
  prompt_with_default OPENCODE_HOSTNAME "OpenCode hostname"
  prompt_with_default OPENCODE_MDNS_DOMAIN "mDNS domain"
  prompt_with_default OPENCODE_USERNAME "Web username"
  prompt_with_default AZURE_RESOURCE_NAME "Azure resource name"
  prompt_with_default OLLAMA_LOCAL_URL "Ollama URL (local or LAN, eg. http://192.168.1.61:11434)"
  prompt_if_empty KOSZYCKAKAPRYS_AZURE_API_KEY "Azure API key (KOSZYCKAKAPRYS_AZURE_API_KEY)" true
  prompt_if_empty OLLAMA_CLOUD_TOKEN "Ollama Cloud token (OLLAMA_CLOUD_TOKEN)" true
  prompt_if_empty OPENCODE_PASSWORD "OpenCode web password (OPENCODE_PASSWORD)" true
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

AZURE_URL="${AZURE_URL:-https://koszyckakaprys.openai.azure.com}"
AZURE_API_KEY="${KOSZYCKAKAPRYS_AZURE_API_KEY:-}"
OLLAMA_LOCAL_URL="${OLLAMA_LOCAL_URL:-https://api-ollama.studio-colorbox.com}"
OLLAMA_CLOUD_TOKEN="${OLLAMA_CLOUD_TOKEN:-}"
CONFIG_DIR="${HOME}/.config/opencode"
CONFIG_FILE="${CONFIG_DIR}/opencode.json"

if [[ -z "${AZURE_API_KEY}" ]]; then
  echo "Missing KOSZYCKAKAPRYS_AZURE_API_KEY for model discovery." >&2
  exit 1
fi

if [[ -z "${OLLAMA_CLOUD_TOKEN}" ]]; then
  echo "Missing OLLAMA_CLOUD_TOKEN for model discovery." >&2
  exit 1
fi

mkdir -p "${CONFIG_DIR}"
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
export AZURE_MODELS_JSON_B64 OLLAMA_LOCAL_JSON_B64 OLLAMA_CLOUD_JSON_B64 CONFIG_FILE

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
    for i in items:
        model_id = i.get('id')
        model_name = i.get('name')
        if model_id and model_name:
            out[model_id] = {'name': model_name}
    return out

config = {
    "$schema": "https://opencode.ai/config.json",
    "model": "azure-koszycka/gpt-5.4",
    "small_model": "azure-koszycka/gpt-4.1",
    "server": {
        "port": ${OPENCODE_PORT:-4096},
        "hostname": "${OPENCODE_HOSTNAME:-0.0.0.0}",
        "mdns": True,
        "mdnsDomain": "${OPENCODE_MDNS_DOMAIN:-opencode.local}"
    },
    "provider": {
        "azure-koszycka": {
            "npm": "@ai-sdk/azure",
            "name": "Azure (koszyckakaprys)",
            "options": {
                "resourceName": "${AZURE_RESOURCE_NAME:-koszyckakaprys}",
                "apiKey": "{env:KOSZYCKAKAPRYS_AZURE_API_KEY}",
                "useCompletionUrls": True
            },
            "models": to_map(azure_models)
        },
        "ollama-local": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "Ollama (Local)",
            "options": {
                "baseURL": "${OLLAMA_LOCAL_URL:-https://api-ollama.studio-colorbox.com}/v1"
            },
            "models": to_map(ollama_local)
        },
        "ollama-cloud-free": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "Ollama Cloud (Free usable)",
            "options": {
                "baseURL": "https://ollama.com/v1",
                "apiKey": "${OLLAMA_CLOUD_TOKEN}"
            },
            "models": to_map(ollama_cloud)
        }
    }
}

with open(os.environ["CONFIG_FILE"], "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)
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
Environment=OPENCODE_SERVER_USERNAME=${OPENCODE_USERNAME}
Environment=OPENCODE_SERVER_PASSWORD=${OPENCODE_PASSWORD}
Environment=OPENCODE_DISABLE_MODELS_FETCH=true

[Install]
WantedBy=default.target
EOF

  cat > "${HOME}/.config/systemd/user/opencode-web.service.d/override.conf" <<EOF
[Service]
WorkingDirectory=${PROJECT_DIR}
EOF
}

write_helpers() {
  mkdir -p "${HOME}/.local/bin"

  cat > "${HOME}/.local/bin/oc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SERVER_URL="${OPENCODE_ATTACH_URL:-http://127.0.0.1:4096}"
REMOTE_DIR="${PWD}"
unit_env="$(systemctl --user show opencode-web --property=Environment --value 2>/dev/null || true)"
username="${OPENCODE_SERVER_USERNAME:-}"
password="${OPENCODE_SERVER_PASSWORD:-}"

if [[ -z "${username}" ]]; then
  username="$(printf '%s\n' "${unit_env}" | sed -n 's/.*OPENCODE_SERVER_USERNAME=\([^ ]*\).*/\1/p')"
fi
if [[ -z "${password}" ]]; then
  password="$(printf '%s\n' "${unit_env}" | sed -n 's/.*OPENCODE_SERVER_PASSWORD=\([^ ]*\).*/\1/p')"
fi

args=(attach "${SERVER_URL}" --dir "${REMOTE_DIR}")
[[ -n "${username}" ]] && args+=(--username "${username}")
[[ -n "${password}" ]] && args+=(--password "${password}")
exec "${HOME}/.opencode/bin/opencode" "${args[@]}" "$@"
EOF

  cat > "${HOME}/.local/bin/oc-web-here" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

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
WorkingDirectory=${target_dir}
EOT

systemctl --user daemon-reload
systemctl --user restart opencode-web
sleep 2

if systemctl --user is-active opencode-web >/dev/null 2>&1; then
  echo "opencode-web now serves: ${target_dir}"
  echo "Local URL: http://127.0.0.1:4096"
else
  echo "opencode-web failed to start for ${target_dir}" >&2
  systemctl --user status opencode-web --no-pager >&2 || true
  exit 1
fi
EOF

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

  install_opencode
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
  echo "Web: http://127.0.0.1:${OPENCODE_PORT}"
  echo "Use in project dir: oc"
  echo "Switch web project: oc-web-here"
}

main "$@"
