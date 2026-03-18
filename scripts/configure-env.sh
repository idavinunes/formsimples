#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
EXAMPLE_FILE="${ROOT_DIR}/.env.example"

get_value() {
  local key="$1"
  local file="$2"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  awk -F= -v key="$key" '
    $1 == key {
      sub(/^[^=]*=/, "", $0)
      print $0
      exit
    }
  ' "$file"
}

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

prompt_secret() {
  local label="$1"
  local default_value="$2"
  local result=""

  if [[ -n "$default_value" ]]; then
    read -r -s -p "${label} [valor atual mantido se vazio]: " result
  else
    read -r -s -p "${label}: " result
  fi
  printf '\n'

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

prompt_number() {
  local label="$1"
  local default_value="$2"
  local min_value="$3"
  local max_value="${4:-}"
  local result=""

  while true; do
    result="$(prompt_value "$label" "$default_value")"

    if [[ ! "$result" =~ ^[0-9]+$ ]]; then
      echo "Informe apenas numeros."
      continue
    fi

    if (( result < min_value )); then
      echo "Informe um valor maior ou igual a ${min_value}."
      continue
    fi

    if [[ -n "$max_value" ]] && (( result > max_value )); then
      echo "Informe um valor menor ou igual a ${max_value}."
      continue
    fi

    printf '%s' "$result"
    return
  done
}

current_port="$(get_value PORT "$ENV_FILE")"
current_host="$(get_value HOST "$ENV_FILE")"
current_webhook_url="$(get_value WEBHOOK_URL "$ENV_FILE")"
current_auth_name="$(get_value WEBHOOK_AUTH_HEADER_NAME "$ENV_FILE")"
current_auth_value="$(get_value WEBHOOK_AUTH_HEADER_VALUE "$ENV_FILE")"
current_timeout="$(get_value PROXY_TIMEOUT_MS "$ENV_FILE")"

default_host="${current_host:-$(get_value HOST "$EXAMPLE_FILE")}"
default_port="${current_port:-$(get_value PORT "$EXAMPLE_FILE")}"
default_webhook_url="${current_webhook_url:-$(get_value WEBHOOK_URL "$EXAMPLE_FILE")}"
default_timeout="${current_timeout:-$(get_value PROXY_TIMEOUT_MS "$EXAMPLE_FILE")}"

default_host="${default_host:-127.0.0.1}"
default_port="${default_port:-4173}"
default_timeout="${default_timeout:-45000}"

echo
echo "Configuracao do arquivo .env"
echo "Projeto: ${ROOT_DIR}"
echo

port="$(prompt_number "Porta local do servidor" "$default_port" 1 65535)"
host="$(prompt_value "Host do servidor (use 127.0.0.1 com cloudflared)" "$default_host")"
webhook_url="$(prompt_value "URL do webhook do n8n" "$default_webhook_url")"

auth_default="nao"
if [[ -n "$current_auth_name" || -n "$current_auth_value" ]]; then
  auth_default="sim"
fi

use_auth="$(prompt_yes_no "Deseja usar header de autenticacao no webhook?" "$auth_default")"

auth_header_name=""
auth_header_value=""
if [[ "$use_auth" == "sim" ]]; then
  auth_header_name="$(prompt_value "Nome do header" "${current_auth_name:-Authorization}")"
  auth_header_value="$(prompt_secret "Valor do header" "$current_auth_value")"
fi

timeout_ms="$(prompt_number "Timeout do proxy em milissegundos" "$default_timeout" 5000)"

if [[ -f "$ENV_FILE" ]]; then
  backup_file="${ENV_FILE}.backup.$(date +%Y%m%d%H%M%S)"
  cp "$ENV_FILE" "$backup_file"
  echo
  echo "Backup criado em: ${backup_file}"
fi

{
  printf 'HOST=%s\n' "$host"
  printf 'PORT=%s\n' "$port"
  printf 'WEBHOOK_URL=%s\n' "$webhook_url"
  printf 'WEBHOOK_AUTH_HEADER_NAME=%s\n' "$auth_header_name"
  printf 'WEBHOOK_AUTH_HEADER_VALUE=%s\n' "$auth_header_value"
  printf 'PROXY_TIMEOUT_MS=%s\n' "$timeout_ms"
} > "$ENV_FILE"

echo
echo "Arquivo .env atualizado com sucesso."
echo "- HOST=${host}"
echo "- PORT=${port}"
if [[ -n "$webhook_url" ]]; then
  echo "- WEBHOOK_URL configurado"
else
  echo "- WEBHOOK_URL vazio (modo local)"
fi

if [[ -n "$auth_header_name" ]]; then
  echo "- Header de autenticacao: ${auth_header_name}"
else
  echo "- Header de autenticacao: nao configurado"
fi

echo "- PROXY_TIMEOUT_MS=${timeout_ms}"
