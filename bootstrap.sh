#!/usr/bin/env bash
# bootstrap.sh - Prepare configuration, validate environment, generate secrets, and launch docker-compose
#
# This script:
# - Creates config directories if missing
# - Validates required .env variables
# - Generates password hashes for Caddy basic auth
# - Renders Caddyfile template with environment substitution
# - Runs all docker-compose*.yml files found next to the script
#
# Modes:
#   Default: bring services up (compose up -d)
#   --down : stop services (compose down)
#
# Profiles (compose):
#   By default the script will ENABLE all known profiles.
#   Known profiles: "dozzle"
#
#   You can selectively DISABLE any of those profiles using flags:
#     --no-dozzle      : disable the "dozzle" profile
#
# Examples:
#   $(basename "$0")
#   $(basename "$0") --down
#   $(basename "$0") --no-dozzle
#
set -euo pipefail
IFS=$'\n\t'

###############################################################################
# Colors (portable-ish): red for error, orange-ish for warn if possible
###############################################################################
_init_colors() {
  RED=""
  ORANGE=""
  GREEN=""
  RESET=""

  if command -v tput >/dev/null 2>&1; then
    RESET="$(tput sgr0 2>/dev/null || true)"
  else
    RESET=$'\033[0m'
  fi

  if [[ "${TERM:-}" == *256color* ]]; then
    ORANGE=$'\033[38;5;208m'
    RED=$'\033[31m'
    GREEN=$'\033[32m'
  else
    if command -v tput >/dev/null 2>&1; then
      RED="$(tput setaf 1 2>/dev/null || true)"
      ORANGE="$(tput setaf 3 2>/dev/null || true)"
      GREEN="$(tput setaf 2 2>/dev/null || true)"
      [ -z "$RED" ] && RED=$'\033[31m'
      [ -z "$ORANGE" ] && ORANGE=$'\033[33m'
      [ -z "$GREEN" ] && GREEN=$'\033[32m'
    else
      RED=$'\033[31m'
      ORANGE=$'\033[33m'
      GREEN=$'\033[32m'
    fi
  fi

  if [[ ! -t 2 ]]; then
    RED=""
    ORANGE=""
    GREEN=""
    RESET=""
  fi
}

_init_colors
time_stamp() { date +"%Y-%m-%d %H:%M:%S"; }
err()  { printf '%s %sERROR:%s %s\n' "$(time_stamp)" "$RED" "$RESET" "$*" >&2; }
warn() { printf '%s %sWARN:%s %s\n'  "$(time_stamp)" "$ORANGE" "$RESET" "$*" >&2; }
info() { printf '%s %sINFO:%s %s\n' "$(time_stamp)" "$GREEN" "$RESET" "$*"; }

cleanup_tmpfiles() {
  if [[ "${TMP_FILES_CREATED:-}" == "1" ]]; then
    for f in "${TMP_FILES[@]:-}"; do
      [[ -f "$f" ]] && rm -f "$f" || true
    done
  fi
}

cleanup_secrets() {
  if [[ -d "${SECRETS_PATH:-}" ]]; then
    info "Cleaning up secrets directory..."
    rm -rf "$SECRETS_PATH"
  fi
}

cleanup_all() {
  cleanup_tmpfiles
  #cleanup_secrets
}
trap cleanup_all EXIT

###############################################################################
# Parse args
###############################################################################
MODE="up"

# Profile enable flags (defaults: enabled)
ENABLE_DOZZLE=1
ENABLE_TAILSCALE=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [--down] [--no-dozzle] [-h|--help]

Modes:
  (default)         : bring services up (docker compose up -d)
  --down            : stop services (docker compose down)

Profile control (defaults: all enabled):
  --no-dozzle       : disable the "dozzle" profile
  --no-tailscale    : disable the "tailscale" profile

Examples:
  $(basename "$0")
  $(basename "$0") --down
  $(basename "$0") --no-dozzle
EOF
}

POSITIONAL=()
while (( "$#" )); do
  case "$1" in
    --down) MODE="down"; shift ;;
    --no-dozzle) ENABLE_DOZZLE=0; shift ;;
    --no-tailscale) ENABLE_TAILSCALE=0; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL[@]:-}"

###############################################################################
# Locate script dir and load .env
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  err ".env not found in script directory ($SCRIPT_DIR). Please create it from .env.example."
  exit 2
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

###############################################################################
# Required variables validation
###############################################################################
: "${DOMAIN:?"DOMAIN is not set in .env"}"
: "${VOLUMES_PATH:?"VOLUMES_PATH is not set in .env"}"

if [ -z "${CADDY_AUTH_USER:-}" ] || [ -z "${CADDY_AUTH_PASSWORD:-}" ]; then
  err "CADDY_AUTH_USER and CADDY_AUTH_PASSWORD must be set in .env. Exiting."
  exit 3
fi

if [ -z "${TS_AUTHKEY:-}" ] && [ $ENABLE_TAILSCALE -eq 1 ]; then
  warn "TS_AUTHKEY not set. Tailscale service will be disabled."
  ENABLE_TAILSCALE=0
fi

if [ -z "${TS_DOMAIN:-}" ] && [ $ENABLE_TAILSCALE -eq 1 ]; then
  warn "TS_DOMAIN not set. Tailscale URLs in Caddy might not work correctly."
fi

###############################################################################
# Show summary
###############################################################################
echo
echo "==== alpargati-pi bootstrap - summary ===="
echo "Timezone:                   ${TZ:-<not set>}"
echo "Mode:                       ${MODE}"
echo "Domain:                     ${DOMAIN}"
echo "Volumes path:               ${VOLUMES_PATH}"
echo "Data path:                  ${DATA_PATH:-<not set>}"
echo "Script directory:           ${SCRIPT_DIR}"

echo "Compose profiles (defaults: enabled):"
printf "  - dozzle     : %s\n" "$( [[ $ENABLE_DOZZLE -eq 1 ]] && echo "enabled" || echo "disabled" )"
printf "  - tailscale  : %s\n" "$( [[ $ENABLE_TAILSCALE -eq 1 ]] && echo "enabled" || echo "disabled" )"

echo "=========================================="
echo

###############################################################################
# Ensure directories exist
###############################################################################
if [[ ! -d "$VOLUMES_PATH" ]]; then
  warn "Volumes directory does not exist; creating: $VOLUMES_PATH"
  if ! mkdir -p "$VOLUMES_PATH" 2>/dev/null; then
    err "Could not create Volumes directory: $VOLUMES_PATH"
    echo "Please run: sudo mkdir -p $VOLUMES_PATH && sudo chown -R $(id -u):$(id -g) $(dirname "$VOLUMES_PATH")"
    exit 4
  fi
else
  info "Volumes directory exists: $VOLUMES_PATH"
fi

if [[ -n "${DATA_PATH:-}" ]] && [[ ! -d "$DATA_PATH" ]]; then
  warn "Data directory does not exist; creating: $DATA_PATH"
  if ! mkdir -p "$DATA_PATH" 2>/dev/null; then
    err "Could not create Data directory: $DATA_PATH"
    echo "Please run: sudo mkdir -p $DATA_PATH && sudo chown -R $(id -u):$(id -g) $(dirname "$DATA_PATH")"
    exit 4
  fi
fi

###############################################################################
# Create secrets directory
###############################################################################
SECRETS_PATH="$SCRIPT_DIR/secrets"
mkdir -p "$SECRETS_PATH"
export SECRETS_PATH
info "Secrets directory: $SECRETS_PATH"

###############################################################################
# Determine PUID and PGID from current user
###############################################################################
PUID="$(id -u)"
PGID="$(id -g)"
export PUID PGID

# Detect Docker socket
# Prioritize standard socket for Standard Docker Mode
POSSIBLE_SOCKETS=(
  "/var/run/docker.sock"
  "/run/user/${PUID}/docker.sock"
  "${XDG_RUNTIME_DIR:-/run/user/${PUID}}/docker.sock"
  "$HOME/.docker/run/docker.sock"
)

DOCKER_SOCKET_PATH=""
for socket in "${POSSIBLE_SOCKETS[@]}"; do
  if [[ -S "$socket" ]]; then
    DOCKER_SOCKET_PATH="$socket"
    if [[ "$socket" == "/var/run/docker.sock" ]]; then
      info "Using standard (Root) Docker socket: $DOCKER_SOCKET_PATH"
    else
      info "Detected Rootless Docker socket: $DOCKER_SOCKET_PATH"
    fi
    break
  fi
done

if [[ -z "$DOCKER_SOCKET_PATH" ]]; then
  warn "Docker socket NOT found at standard or Rootless locations."
  # Final fallback to standard root socket as a guess
  DOCKER_SOCKET_PATH="/var/run/docker.sock"
fi

# Ensure DOCKER_HOST is set for compose and containers
export DOCKER_HOST="unix://${DOCKER_SOCKET_PATH}"
export DOCKER_SOCKET_PATH
info "Using PUID=${PUID}, PGID=${PGID}"
info "Using DOCKER_SOCKET_PATH=${DOCKER_SOCKET_PATH}"
info "Using DOCKER_HOST=${DOCKER_HOST}"

###############################################################################
# Generate Caddy bcrypt hash using Docker
###############################################################################
generate_caddy_hash() {
  local user="$1"; local pass="$2"; local hash=""

  # Fallback: htpasswd with -B (Bcrypt) - BEST LOCAL OPTION
  if command -v htpasswd >/dev/null 2>&1; then
    # Try generating with -n (stdout) and -b (batch), -B (bcrypt)
    # Some versions of htpasswd don't support -B, check first
    if htpasswd -nbB "test" "test" >/dev/null 2>&1; then
      hash_line="$(htpasswd -nbB "$user" "$pass" 2>/dev/null || true)"
      hash="${hash_line#*:}"
      if [[ -n "$hash" ]]; then
        echo "$hash"
        return 0
      fi
    fi
  fi

  # Docker fallback - SLOW on Raspberry Pi
  if command -v docker >/dev/null 2>&1; then
    if hash="$(docker run --rm caddy:2 caddy hash-password --plaintext "$pass" 2>/dev/null)"; then
      if [[ -n "$hash" ]]; then
        echo "$hash"
        return 0
      fi
    fi
  fi

  return 1
}

# Create Caddy auth hash
if [[ -n "${CADDY_AUTH_PASSWORD:-}" ]]; then
  # Only generate if missing or secret file doesn't exist
  if [[ ! -f "$SECRETS_PATH/caddy_auth_hash" ]]; then
    CADDY_AUTH_PASSWORD_HASH="$(generate_caddy_hash "$CADDY_AUTH_USER" "$CADDY_AUTH_PASSWORD" || true)"
    if [[ -z "${CADDY_AUTH_PASSWORD_HASH:-}" ]]; then
      err "Failed to generate bcrypt hash for CADDY_AUTH_PASSWORD. Ensure Docker or htpasswd is available."
      exit 5
    fi
    export CADDY_AUTH_PASSWORD_HASH
    info "Generated CADDY_AUTH_PASSWORD_HASH (hidden)."
  else
    CADDY_AUTH_PASSWORD_HASH="$(cat "$SECRETS_PATH/caddy_auth_hash")"
    export CADDY_AUTH_PASSWORD_HASH
    info "Using existing CADDY_AUTH_PASSWORD_HASH."
  fi
fi

###############################################################################
# Write secrets to files
###############################################################################
info "Generating secret files..."

write_secret() {
  local name="$1"
  local value="$2"
  printf '%s' "$value" > "$SECRETS_PATH/$name"
  info "  Created secret: $name"
}

write_secret "ts_authkey" "${TS_AUTHKEY:-}"

info "All secret files generated."

###############################################################################
# Template expansion for Caddyfile
###############################################################################
TMP_FILES_CREATED=0
TMP_FILES=()

expand_vars_file() {
  local src="$1"; local dst="$2"
  if [[ ! -f "$src" ]]; then
    err "Template not found: $src"; return 1
  fi

  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/render.XXXXXX")"
  TMP_FILES_CREATED=1
  TMP_FILES+=("$tmp")

  cp -a "$src" "$tmp"

  # Build sed arguments for placeholders
  sed -i.bak -E 's/\{\{([A-Z0-9_]+)\}\}/\$\{\1\}/g' "$tmp" && rm -f "${tmp}.bak" || true

  if command -v envsubst >/dev/null 2>&1; then
    envsubst < "$tmp" > "$dst"
    info "Rendered $src -> $dst using envsubst"
    return 0
  fi

  if command -v perl >/dev/null 2>&1; then
    perl -0777 -pe 's/\$\{?([A-Z0-9_]+)\}?/exists $ENV{$1} ? $ENV{$1} : $&/ge' "$tmp" > "$dst"
    info "Rendered $src -> $dst using perl"
    return 0
  fi

  warn "envsubst and perl not found; falling back to copy without expansion"
  cp -a "$src" "$dst"
  return 0
}

CADDY_SRC="$SCRIPT_DIR/configs/Caddyfile"
CADDY_DST="$SCRIPT_DIR/configs/Caddyfile.custom"
if [[ -f "$CADDY_SRC" ]]; then
  if ! expand_vars_file "$CADDY_SRC" "$CADDY_DST"; then
    warn "Failed to render Caddyfile; copying original as fallback"
    cp -a "$CADDY_SRC" "$CADDY_DST"
  fi
else
  warn "configs/Caddyfile not found; skipping rendering."
fi

###############################################################################
# Initialize AdGuard Home Configuration (only if not exists)
###############################################################################
ADGUARD_TEMPLATE="$SCRIPT_DIR/configs/AdGuardHome.template.yaml"
ADGUARD_CONF_DIR="$VOLUMES_PATH/adguardhome/conf"
ADGUARD_CONF="$ADGUARD_CONF_DIR/AdGuardHome.yaml"

if [[ -f "$ADGUARD_TEMPLATE" ]]; then
  if [[ ! -f "$ADGUARD_CONF" ]]; then
    info "Initializing AdGuard Home configuration..."
    
    # Detect eth0 IP address (primary network interface on Raspberry Pi)
    ETH0_IP=""
    if command -v ip >/dev/null 2>&1; then
      ETH0_IP=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || true)
    fi
    if [[ -z "$ETH0_IP" ]]; then
      # Fallback to hostname -I (first IP)
      ETH0_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
    fi
    if [[ -z "$ETH0_IP" ]]; then
      warn "Could not detect IP address for AdGuard DNS rewrites. Using placeholder."
      ETH0_IP="192.168.0.1"
    fi
    export ETH0_IP
    info "Detected IP address for DNS rewrites: $ETH0_IP"
    
    # Generate bcrypt hash for AdGuard password
    if [[ -n "${ADGUARD_ADMIN_PASSWORD:-}" ]]; then
      ADGUARD_ADMIN_PASSWORD_HASH=""
      if command -v htpasswd >/dev/null 2>&1; then
        # htpasswd -B generates bcrypt hash
        if htpasswd -nbB "" "$ADGUARD_ADMIN_PASSWORD" >/dev/null 2>&1; then
          ADGUARD_ADMIN_PASSWORD_HASH=$(htpasswd -nbB "" "$ADGUARD_ADMIN_PASSWORD" 2>/dev/null | cut -d: -f2 || true)
        fi
      fi
      if [[ -z "$ADGUARD_ADMIN_PASSWORD_HASH" ]] && command -v docker >/dev/null 2>&1; then
        # Fallback to docker-based hash generation
        ADGUARD_ADMIN_PASSWORD_HASH=$(docker run --rm caddy:2 caddy hash-password --plaintext "$ADGUARD_ADMIN_PASSWORD" 2>/dev/null || true)
      fi
      if [[ -z "$ADGUARD_ADMIN_PASSWORD_HASH" ]]; then
        warn "Could not generate password hash for AdGuard. Manual setup required."
        ADGUARD_ADMIN_PASSWORD_HASH=""
      fi
      export ADGUARD_ADMIN_PASSWORD_HASH
    fi
    
    # Create config directory and render template
    mkdir -p "$ADGUARD_CONF_DIR"
    if expand_vars_file "$ADGUARD_TEMPLATE" "$ADGUARD_CONF"; then
      info "AdGuard Home configuration created at $ADGUARD_CONF"
    else
      warn "Failed to render AdGuard Home configuration"
    fi
  else
    info "AdGuard Home configuration already exists at $ADGUARD_CONF - skipping template"
  fi
else
  info "AdGuard Home template not found; skipping auto-configuration."
fi

###############################################################################
# Determine docker compose command
###############################################################################
if docker compose version >/dev/null 2>&1; then
  compose() { docker compose "$@"; }
elif command -v docker-compose >/dev/null 2>&1; then
  compose() { docker-compose "$@"; }
else
  err "Neither 'docker compose' nor 'docker-compose' found. Install Docker Compose."
  exit 6
fi
info "Compose command wrapper is ready."

# Check profile support
SUPPORTS_PROFILE=0
if compose help up 2>&1 | grep -q -- '--profile'; then
  SUPPORTS_PROFILE=1
else
  if compose --help 2>&1 | grep -q -- '--profile'; then
    SUPPORTS_PROFILE=1
  fi
fi

if [[ $SUPPORTS_PROFILE -eq 0 ]]; then
  warn "Compose implementation does not support '--profile'; profile flags will be ignored."
fi

###############################################################################
# Gather docker-compose files
###############################################################################
shopt -s nullglob
compose_ymls=( "$SCRIPT_DIR"/docker-compose*.yml )
shopt -u nullglob

if [[ ${#compose_ymls[@]} -eq 0 ]]; then
  err "No docker-compose*.yml files found in script directory ($SCRIPT_DIR)."
  exit 7
fi

COMPOSE_PROJECT="alpargati-pi"
compose_args=(-p $COMPOSE_PROJECT)
for f in "${compose_ymls[@]}"; do
  compose_args+=(-f "$f")
done

###############################################################################
# Build profile args for 'compose up' when applicable
###############################################################################
PROFILE_ARGS=()
if [[ $SUPPORTS_PROFILE -eq 1 ]]; then
  if [[ $ENABLE_DOZZLE -eq 1 ]]; then
    PROFILE_ARGS+=( --profile dozzle )
  fi
  if [[ $ENABLE_TAILSCALE -eq 1 ]]; then
    PROFILE_ARGS+=( --profile tailscale )
  fi
fi

###############################################################################
# Unset sensitive variables to prevent leaking into the environment
###############################################################################
info "Unsetting sensitive environment variables..."
unset CADDY_AUTH_PASSWORD
unset CADDY_AUTH_PASSWORD_HASH
unset TS_AUTHKEY
unset TS_API_KEY
unset TS_DEVICE_ID
unset ADGUARD_ADMIN_PASSWORD
unset ADGUARD_ADMIN_PASSWORD_HASH

###############################################################################
# Run compose
###############################################################################
info "Invoking docker compose mode: ${MODE}"

if [[ "$MODE" == "up" ]]; then
  if [[ ${#PROFILE_ARGS[@]} -gt 0 ]]; then
    info "Enabled compose profiles: $(printf '%s ' "${PROFILE_ARGS[@]}")"
  else
    info "No compose profiles will be passed."
  fi

  compose "${compose_args[@]}" "${PROFILE_ARGS[@]:-}" up -d --force-recreate --remove-orphans
  EXIT_CODE=$?
elif [[ "$MODE" == "down" ]]; then
  compose "${compose_args[@]}" "${PROFILE_ARGS[@]:-}" down --remove-orphans
  EXIT_CODE=$?
else
  err "Unknown MODE: $MODE"
  exit 2
fi

if [[ $EXIT_CODE -ne 0 ]]; then
  err "Docker compose command exited with code: $EXIT_CODE"
  exit $EXIT_CODE
fi

info "Compose command finished successfully."
