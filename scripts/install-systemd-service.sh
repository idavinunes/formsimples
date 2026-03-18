#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_SERVICE_NAME="onix-form"
DEFAULT_APP_DIR="$ROOT_DIR"
DEFAULT_NODE_BIN="$(command -v node || true)"
DEFAULT_SERVICE_USER="$(id -un)"
DEFAULT_SERVICE_GROUP="$(id -gn)"

prompt_value() {
  local label="$1"
  local default_value="$2"
  local result=""

  read -r -p "${label} [${default_value}]: " result
  if [[ -z "$result" ]]; then
    result="$default_value"
  fi

  printf '%s' "$result"
}

prompt_yes_no() {
  local label="$1"
  local default_value="$2"
  local result=""

  while true; do
    read -r -p "${label} [${default_value}]: " result
    result="${result:-$default_value}"

    case "${result,,}" in
      s|sim|y|yes)
        printf 'sim'
        return
        ;;
      n|nao|não|no)
        printf 'nao'
        return
        ;;
    esac

    echo "Resposta invalida. Use sim ou nao."
  done
}

run_privileged() {
  if [[ "$EUID" -eq 0 ]]; then
    "$@"
    return
  fi

  sudo "$@"
}

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Este script foi pensado para Linux com systemd."
  exit 1
fi

if [[ ! -d /run/systemd/system ]]; then
  echo "systemd nao encontrado neste ambiente."
  exit 1
fi

if [[ -z "$DEFAULT_NODE_BIN" ]]; then
  echo "Node.js nao encontrado no PATH."
  echo "Instale Node.js 18+ antes de criar o servico."
  exit 1
fi

echo
echo "Instalacao do servico systemd"
echo "Projeto: ${ROOT_DIR}"
echo

service_name="$(prompt_value "Nome do servico" "$DEFAULT_SERVICE_NAME")"
app_dir="$(prompt_value "Diretorio do projeto" "$DEFAULT_APP_DIR")"
service_user="$(prompt_value "Usuario do servico" "$DEFAULT_SERVICE_USER")"
service_group="$(prompt_value "Grupo do servico" "$DEFAULT_SERVICE_GROUP")"
node_bin="$(prompt_value "Caminho do binario node" "$DEFAULT_NODE_BIN")"

if [[ "$app_dir" == *" "* ]]; then
  echo "O diretorio do projeto nao deve conter espacos para este setup."
  exit 1
fi

if [[ ! -d "$app_dir" ]]; then
  echo "Diretorio do projeto nao encontrado: $app_dir"
  exit 1
fi

if [[ ! -f "$app_dir/server.js" ]]; then
  echo "server.js nao encontrado em: $app_dir"
  exit 1
fi

if [[ ! -x "$node_bin" ]]; then
  echo "Binario node invalido: $node_bin"
  exit 1
fi

env_file="${app_dir}/.env"
if [[ ! -f "$env_file" ]]; then
  echo "Arquivo .env nao encontrado em: $env_file"
  echo "Rode antes: ./scripts/configure-env.sh"
  exit 1
fi

service_file="/etc/systemd/system/${service_name}.service"
tmp_service_file="$(mktemp)"

cat > "$tmp_service_file" <<EOF
[Unit]
Description=Onix Saude Web Form
After=network.target

[Service]
Type=simple
User=${service_user}
Group=${service_group}
WorkingDirectory=${app_dir}
ExecStart=${node_bin} ${app_dir}/server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

run_privileged install -m 0644 "$tmp_service_file" "$service_file"
rm -f "$tmp_service_file"

run_privileged systemctl daemon-reload

enable_service="$(prompt_yes_no "Deseja habilitar o servico no boot?" "sim")"
if [[ "$enable_service" == "sim" ]]; then
  run_privileged systemctl enable "$service_name"
fi

start_service="$(prompt_yes_no "Deseja iniciar ou reiniciar o servico agora?" "sim")"
if [[ "$start_service" == "sim" ]]; then
  run_privileged systemctl restart "$service_name"
fi

echo
echo "Servico criado em: ${service_file}"
echo "Comandos uteis:"
echo "- sudo systemctl status ${service_name}"
echo "- sudo systemctl restart ${service_name}"
echo "- sudo journalctl -u ${service_name} -n 100 --no-pager"
echo "- curl http://$(awk -F= '/^HOST=/{print $2; exit}' "$env_file"):$(awk -F= '/^PORT=/{print $2; exit}' "$env_file")/api/health"
