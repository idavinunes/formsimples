#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

node_is_supported() {
  if ! command -v node >/dev/null 2>&1; then
    return 1
  fi

  local major=""
  major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
  [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 18 ))
}

install_node_20() {
  run_privileged apt-get update
  run_privileged apt-get install -y ca-certificates curl gnupg
  run_privileged mkdir -p /etc/apt/keyrings

  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | run_privileged gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
    | run_privileged tee /etc/apt/sources.list.d/nodesource.list >/dev/null

  run_privileged apt-get update
  run_privileged apt-get install -y nodejs
}

echo
echo "Setup do Onix Form para Ubuntu 22.04"
echo "Projeto: ${ROOT_DIR}"
echo

if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "22.04" ]]; then
    echo "Aviso: este script foi preparado para Ubuntu 22.04, mas o sistema atual e ${PRETTY_NAME:-desconhecido}."
    continuar="$(prompt_yes_no "Deseja continuar mesmo assim?" "nao")"
    if [[ "$continuar" != "sim" ]]; then
      exit 1
    fi
  fi
fi

if node_is_supported; then
  echo "Node.js compativel encontrado: $(node -v)"
else
  echo "Node.js 18+ nao encontrado."
  instalar_node="$(prompt_yes_no "Deseja instalar Node.js 20 agora?" "sim")"
  if [[ "$instalar_node" != "sim" ]]; then
    echo "Instale Node.js 18+ e rode este script novamente."
    exit 1
  fi
  install_node_20
  echo "Node.js instalado: $(node -v)"
fi

echo
"${ROOT_DIR}/scripts/configure-env.sh"
echo
"${ROOT_DIR}/scripts/install-systemd-service.sh"

echo
echo "Setup concluido."
